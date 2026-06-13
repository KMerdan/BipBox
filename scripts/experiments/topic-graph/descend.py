#!/usr/bin/env python3
"""
Stage A — filesystem descent + node inventory.

Walks the configured roots and decides, for every directory, whether it is a
*unit* (stop, emit one node) or a *container* (descend). That single decision is
both the folder-vs-project distinction AND the depth decision.

Output:
  - nodes.jsonl : one JSON object per emitted node (project | bundle | file)
  - a human-readable summary to stdout (the eyeball test for the descent itself)

This is throwaway research code. Its *logic* (not the language) ports to a Swift
`FilesystemDescender` that replaces DefaultColdStartScanner's binary recursive
flag. No third-party deps — stdlib only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, asdict, field
from pathlib import Path

# --------------------------------------------------------------------------
# Rules (these are the knobs we'll port verbatim to Swift)
# --------------------------------------------------------------------------

# Directories we never enter and never emit. The big one missing from the
# current Swift scanner: it only skips hidden files, so it walks node_modules.
PRUNE_DIRS = {
    "node_modules", ".build", ".git", "DerivedData", "target", "dist", "build",
    "__pycache__", ".venv", "venv", "env", "vendor", "Pods", ".next", ".nuxt",
    ".gradle", ".idea", ".cache", ".pytest_cache", ".mypy_cache", ".tox",
    "Carthage", ".terraform", "bin", "obj", ".dart_tool", ".svelte-kit",
}

# Exact-name markers that make a directory a PROJECT (stop + emit one node).
PROJECT_MARKERS = {
    ".git", "Package.swift", "package.json", "Cargo.toml", "go.mod",
    "pyproject.toml", "pom.xml", "build.gradle", "build.gradle.kts", "Gemfile",
    "requirements.txt", "setup.py", "Makefile", "CMakeLists.txt", "composer.json",
    "pubspec.yaml", ".project", "mix.exs", "Dockerfile",
}
PROJECT_MARKER_SUFFIXES = (".xcodeproj", ".xcworkspace")

# Manifests that mean "this project owns child projects" → emit children too.
WORKSPACE_MANIFESTS = {
    "pnpm-workspace.yaml", "go.work", "lerna.json", "nx.json", "turbo.json",
}

# Bundle/package directory suffixes (treated as a single opaque unit).
BUNDLE_SUFFIXES = (
    ".app", ".framework", ".bundle", ".photoslibrary", ".rtfd", ".xcassets",
    ".playground", ".framework", ".plugin", ".kext", ".docset",
)

# File-type buckets (mirrors WorkspaceModel.typeCategory so the inventory maps
# straight onto the app's categories).
MEDIA_EXTS = {"png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "tiff", "bmp",
              "mp4", "mov", "m4v", "avi", "mkv", "webm", "mp3", "wav", "aac",
              "m4a", "flac", "aiff"}
DOC_EXTS = {"pdf", "doc", "docx", "pages", "txt", "md", "rtf", "odt",
            "csv", "xls", "xlsx", "numbers", "tsv", "key", "ppt", "pptx", "epub"}
CODE_EXTS = {"swift", "js", "ts", "tsx", "jsx", "py", "java", "c", "cpp", "h",
             "hpp", "rb", "go", "rs", "json", "yaml", "yml", "html", "css",
             "sh", "kt", "m", "mm", "sql", "toml", "xml", "php", "lua", "r"}
ARCHIVE_EXTS = {"zip", "dmg", "tar", "gz", "tgz", "rar", "7z", "bz2", "pkg", "iso"}

# Files whose only meaningful signal is metadata (no topic content). These are
# tracked separately so they never pollute the topic graph.
def content_bearing(ext: str, category: str) -> bool:
    return category in ("Documents", "Code", "Spreadsheets")


def category_for(ext: str) -> str:
    if ext in DOC_EXTS and ext not in {"csv", "xls", "xlsx", "numbers", "tsv"}:
        return "Documents"
    if ext in {"csv", "xls", "xlsx", "numbers", "tsv"}:
        return "Spreadsheets"
    if ext in MEDIA_EXTS:
        return "Media"
    if ext in CODE_EXTS:
        return "Code"
    if ext in ARCHIVE_EXTS:
        return "Archives"
    return "Other"


# --------------------------------------------------------------------------

@dataclass
class Node:
    id: str
    type: str            # project | bundle | collection | file
    path: str
    root: str
    depth: int
    parent_id: str | None = None
    # project-only
    nature: str | None = None         # project | workspace-member
    markers: list[str] = field(default_factory=list)
    languages: list[str] = field(default_factory=list)
    child_count: int | None = None
    # collection-only
    member_count: int | None = None           # all files in the subtree
    content_member_count: int | None = None    # content-bearing members
    categories: list[str] = field(default_factory=list)
    # file-only
    collection_id: str | None = None  # set when this file belongs to a collection
    category: str | None = None
    ext: str | None = None
    content_bearing: bool | None = None
    size: int | None = None
    # Tier-0 dedup: cheap structural fingerprint "size:blake2(head):blake2(tail)".
    # Name-independent (catches renamed copies). Near-dups (same meaning, different
    # bytes) are collapsed later by cosine≳0.97 at embed time, not here.
    byte_fp: str | None = None


def node_id(path: str) -> str:
    return hashlib.sha1(path.encode("utf-8")).hexdigest()[:16]


@dataclass
class Stats:
    roots: dict = field(default_factory=dict)
    projects: int = 0
    workspace_members: int = 0
    bundles: int = 0
    collections: int = 0
    collection_members: int = 0
    files: int = 0
    content_files: int = 0
    metaonly_files: int = 0
    pruned: Counter = field(default_factory=Counter)
    permission_denied: int = 0
    max_depth_hits: int = 0
    file_categories: Counter = field(default_factory=Counter)
    project_natures: Counter = field(default_factory=Counter)
    depth_hist: Counter = field(default_factory=Counter)
    project_list: list = field(default_factory=list)
    collection_list: list = field(default_factory=list)
    fp_counts: Counter = field(default_factory=Counter)  # byte_fp -> count (exact dups)


def is_project(entries: list[os.DirEntry]) -> list[str]:
    """Return the matched project markers (empty = not a project)."""
    names = {e.name for e in entries}
    matched = [m for m in PROJECT_MARKERS if m in names]
    for e in entries:
        if e.name.endswith(PROJECT_MARKER_SUFFIXES):
            matched.append(e.name)
    return matched


def has_workspace_manifest(entries: list[os.DirEntry]) -> bool:
    names = {e.name for e in entries}
    if names & WORKSPACE_MANIFESTS:
        return True
    # Cargo workspace lives inside Cargo.toml — cheap text peek.
    for e in entries:
        if e.name == "Cargo.toml":
            try:
                if "[workspace]" in Path(e.path).read_text(errors="ignore"):
                    return True
            except OSError:
                pass
    return False


def project_languages(dirpath: str, limit_dirs: int = 200) -> list[str]:
    """Top source-file extensions inside a project (bounded walk, skips prune dirs)."""
    counts: Counter = Counter()
    seen_dirs = 0
    for cur, dirs, files in os.walk(dirpath):
        dirs[:] = [d for d in dirs if d not in PRUNE_DIRS and not d.startswith(".")]
        seen_dirs += 1
        if seen_dirs > limit_dirs:
            break
        for f in files:
            ext = Path(f).suffix.lower().lstrip(".")
            if ext in CODE_EXTS:
                counts[ext] += 1
    return [ext for ext, _ in counts.most_common(4)]


def scandir_safe(path: str, stats: Stats) -> list[os.DirEntry]:
    try:
        with os.scandir(path) as it:
            return list(it)
    except PermissionError:
        stats.permission_denied += 1
        return []
    except OSError:
        return []


def emit_project(entry_path: str, root: str, depth: int, markers: list[str],
                 nature: str, parent_id: str | None, out, stats: Stats,
                 child_count: int | None = None) -> str:
    nid = node_id(entry_path)
    n = Node(
        id=nid, type="project", path=entry_path, root=root, depth=depth,
        parent_id=parent_id, nature=nature, markers=sorted(set(markers)),
        languages=project_languages(entry_path), child_count=child_count,
    )
    out.write(json.dumps(asdict(n)) + "\n")
    if nature == "workspace-member":
        stats.workspace_members += 1
    else:
        stats.projects += 1
    stats.project_natures[nature] += 1
    stats.project_list.append((Path(entry_path).name, entry_path, n.markers, n.languages))
    return nid


def byte_fp(path: str, size: int | None) -> str | None:
    """Tier-0 structural fingerprint: size + blake2 of head/tail (no full read)."""
    if size is None:
        return None
    try:
        with open(path, "rb") as f:
            head = f.read(4096)
            if size > 8192:
                f.seek(-4096, os.SEEK_END)
                tail = f.read(4096)
            else:
                tail = b""
        h = hashlib.blake2b(digest_size=8)
        h.update(head)
        h.update(tail)
        return f"{size}:{h.hexdigest()}"
    except OSError:
        return None


def dir_has_project_child(dirs: list[os.DirEntry], stats: Stats) -> bool:
    """A non-project folder is a *container* (descend) if any immediate subdir is
    itself a project; otherwise it's a *collection* (collapse). One-level lookahead
    — nested-project-under-docs is a rare miss we accept for the experiment."""
    for d in dirs:
        if d.name in PRUNE_DIRS or d.name.startswith("."):
            continue
        if is_project(scandir_safe(d.path, stats)):
            return True
    return False


def gather_member_files(root_dir: str) -> list[str]:
    """All non-symlink files under a collection subtree, pruning junk dirs."""
    out: list[str] = []
    for cur, dirs, files in os.walk(root_dir):
        dirs[:] = [d for d in dirs if d not in PRUNE_DIRS and not d.startswith(".")]
        for f in files:
            p = os.path.join(cur, f)
            if os.path.islink(p):
                continue
            out.append(p)
    return out


def emit_file(path: str, root: str, depth: int, parent_id: str | None,
              out, stats: Stats, collection_id: str | None = None):
    name = os.path.basename(path)
    ext = Path(name).suffix.lower().lstrip(".")
    cat = category_for(ext)
    cb = content_bearing(ext, cat)
    try:
        size = os.stat(path, follow_symlinks=False).st_size
    except OSError:
        size = None
    fp = byte_fp(path, size)
    n = Node(
        id=node_id(path), type="file", path=path, root=root, depth=depth,
        parent_id=parent_id, collection_id=collection_id, category=cat,
        ext=ext or None, content_bearing=cb, size=size, byte_fp=fp,
    )
    out.write(json.dumps(asdict(n)) + "\n")
    stats.files += 1
    stats.file_categories[cat] += 1
    if fp:
        stats.fp_counts[fp] += 1
    if cb:
        stats.content_files += 1
    else:
        stats.metaonly_files += 1


def emit_collection(path: str, root: str, depth: int, parent_id: str | None,
                    out, stats: Stats):
    """A non-project folder = one collection node (the folder IS the topic) + every
    member file indexed individually (so semantic search hits the exact file)."""
    cid = node_id(path)
    # Walk the subtree, but SPLIT OUT any nested project as its own node (child of
    # this collection) and prune its files — a collection never swallows a project.
    members: list[str] = []
    nested = 0
    for cur, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if d not in PRUNE_DIRS and not d.startswith(".")]
        keep = []
        for d in dirs:
            dpath = os.path.join(cur, d)
            mk = is_project(scandir_safe(dpath, stats))
            if mk:
                rel = dpath[len(path):].strip(os.sep).count(os.sep)
                emit_project(dpath, root, depth + 1 + rel, mk, "project",
                             cid, out, stats)
                nested += 1
            else:
                keep.append(d)
        dirs[:] = keep  # prune split-out projects from further descent
        for f in files:
            p = os.path.join(cur, f)
            if not os.path.islink(p):
                members.append(p)
    cats: Counter = Counter()
    content = 0
    for p in members:
        ext = Path(p).suffix.lower().lstrip(".")
        c = category_for(ext)
        cats[c] += 1
        if content_bearing(ext, c):
            content += 1
    n = Node(
        id=cid, type="collection", path=path, root=root, depth=depth,
        parent_id=parent_id, member_count=len(members), content_member_count=content,
        categories=[c for c, _ in cats.most_common(4)], child_count=nested or None,
    )
    out.write(json.dumps(asdict(n)) + "\n")
    stats.collections += 1
    stats.collection_members += len(members)
    stats.collection_list.append((Path(path).name, path, len(members), content, n.categories))
    for p in members:
        emit_file(p, root, depth + 1, cid, out, stats, collection_id=cid)
    return cid


def walk(path: str, depth: int, root: str, parent_id: str | None,
         out, stats: Stats, max_depth: int):
    stats.depth_hist[depth] += 1
    entries = scandir_safe(path, stats)
    if not entries and depth > 0:
        return

    dirs, files = [], []
    for e in entries:
        try:
            if e.is_symlink():
                continue
            if e.is_dir(follow_symlinks=False):
                dirs.append(e)
            elif e.is_file(follow_symlinks=False):
                files.append(e)
        except OSError:
            continue

    # --- classify THIS directory (skip the synthetic root level) ---
    if depth > 0:
        name = Path(path).name
        if name.endswith(BUNDLE_SUFFIXES):
            nid = node_id(path)
            out.write(json.dumps(asdict(Node(
                id=nid, type="bundle", path=path, root=root, depth=depth,
                parent_id=parent_id, nature="bundle"))) + "\n")
            stats.bundles += 1
            return  # opaque unit — never descend

        markers = is_project(entries)
        if markers:
            child_projects = []
            if has_workspace_manifest(entries):
                for d in dirs:
                    if d.name in PRUNE_DIRS or d.name.startswith("."):
                        continue
                    sub_entries = scandir_safe(d.path, stats)
                    if is_project(sub_entries):
                        child_projects.append(d)
            pid = emit_project(path, root, depth, markers, "project",
                               parent_id, out, stats,
                               child_count=len(child_projects) or None)
            for d in child_projects:
                emit_project(d.path, root, depth + 1, is_project(scandir_safe(d.path, stats)),
                             "workspace-member", pid, out, stats)
            return  # STOP — a project is one unit; don't descend for file nodes

        # Non-project folder: container (holds projects → descend) or collection
        # (the folder IS the topic → collapse the whole subtree into one node).
        if not dir_has_project_child(dirs, stats):
            emit_collection(path, root, depth, parent_id, out, stats)
            return  # STOP — collection collapses its subtree (no depth truncation)

    # --- container (or root): emit loose files here, then descend ---
    for f in files:
        emit_file(f.path, root, depth, parent_id, out, stats)

    if depth >= max_depth:
        stats.max_depth_hits += 1
        return

    for d in dirs:
        if d.name in PRUNE_DIRS or d.name.startswith("."):
            stats.pruned[d.name] += 1
            continue
        walk(d.path, depth + 1, root, parent_id, out, stats, max_depth)


def main():
    ap = argparse.ArgumentParser(description="Stage A: filesystem descent + inventory")
    ap.add_argument("--roots", nargs="+",
                    default=[str(Path.home() / "Downloads"),
                             str(Path.home() / "localGit")])
    ap.add_argument("--max-depth", type=int, default=5)
    ap.add_argument("--out", default=str(Path(__file__).parent / "nodes.jsonl"))
    args = ap.parse_args()

    stats = Stats()
    with open(args.out, "w") as out:
        for root in args.roots:
            if not os.path.isdir(root):
                print(f"  skip (missing): {root}", file=sys.stderr)
                continue
            before = (stats.projects + stats.workspace_members, stats.files,
                      stats.bundles, stats.collections)
            walk(root, 0, root, None, out, stats, args.max_depth)
            after = (stats.projects + stats.workspace_members, stats.files,
                     stats.bundles, stats.collections)
            stats.roots[root] = {
                "projects": after[0] - before[0],
                "files": after[1] - before[1],
                "bundles": after[2] - before[2],
                "collections": after[3] - before[3],
            }

    print_report(stats, args)


def print_report(stats: Stats, args):
    line = "=" * 64
    print(line)
    print("STAGE A — DESCENT INVENTORY")
    print(line)
    print(f"roots (max-depth={args.max_depth}):")
    for r, c in stats.roots.items():
        print(f"  {r}")
        print(f"      projects={c['projects']:<4} collections={c['collections']:<4} "
              f"files={c['files']:<6} bundles={c['bundles']}")
    print(line)
    print(f"projects (units):     {stats.projects}")
    print(f"  workspace members:  {stats.workspace_members}")
    print(f"collections (units):  {stats.collections}  ({stats.collection_members} member files)")
    print(f"bundles:              {stats.bundles}")
    print(f"files (total):        {stats.files}")
    print(f"  content-bearing:    {stats.content_files}  (eligible for topic graph)")
    print(f"  metadata-only:      {stats.metaonly_files}  (by-type lane, excluded from topics)")
    print(f"permission denied:    {stats.permission_denied} dirs")
    print(f"max-depth cutoffs:    {stats.max_depth_hits}")
    # Tier-0 exact-dup groups (same size + head/tail bytes, any name).
    dup_groups = {fp: c for fp, c in stats.fp_counts.items() if c > 1}
    dup_extra = sum(c - 1 for c in dup_groups.values())
    print(f"exact-dup groups:     {len(dup_groups)}  ({dup_extra} redundant copies, "
          f"{100*dup_extra/max(stats.files,1):.0f}% of files)")
    print(line)
    print("file categories:")
    for cat, n in stats.file_categories.most_common():
        print(f"  {cat:<14} {n}")
    print(line)
    print("top pruned dir names (dirs skipped):")
    for name, n in stats.pruned.most_common(12):
        print(f"  {name:<18} {n}")
    print(line)
    print(f"detected projects ({len(stats.project_list)}):")
    for name, path, markers, langs in sorted(stats.project_list, key=lambda x: x[1])[:60]:
        m = ",".join(markers[:3])
        lg = ",".join(langs) if langs else "-"
        short = path.replace(str(Path.home()), "~")
        print(f"  {name:<28} [{m}] langs={lg}")
        print(f"      {short}")
    if len(stats.project_list) > 60:
        print(f"  … and {len(stats.project_list) - 60} more")
    print(line)
    print(f"collections ({len(stats.collection_list)}):")
    for name, path, members, content, cats in sorted(
            stats.collection_list, key=lambda x: -x[2])[:40]:
        short = path.replace(str(Path.home()), "~")
        print(f"  {name:<32} {members:>5} files ({content} content)  {','.join(cats)}")
        print(f"      {short}")
    if len(stats.collection_list) > 40:
        print(f"  … and {len(stats.collection_list) - 40} more")
    print(line)
    print(f"nodes written → {args.out}")


if __name__ == "__main__":
    main()
