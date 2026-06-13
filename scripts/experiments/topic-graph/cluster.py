#!/usr/bin/env python3
"""
Stage D — topic discovery (Swift-portable) + soft, overlapping membership.

Pipeline (all pure-numpy → ports to Swift; NO hdbscan/umap):
  1. cosine kNN graph over the rich vectors (projects + collections + docs).
  2. Louvain community detection on that graph  ->  topic REGIONS.
  3. centroid per region; extractive label (member nearest centroid + key terms).
  4. SOFT assign EVERY node (incl. data) to topics by cosine-to-centroid, top-k
     above threshold  ->  weighted HAS_TOPIC edges (multi-membership, not a partition).
  5. RELATED_TO = top-k project<->project cosine.

Outputs topics.jsonl + edges.jsonl, and prints the eyeball report.
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

HERE = Path(__file__).parent
KNN = 15                 # neighbors per node in the graph
RESOLUTION = 1.0         # Louvain resolution (higher -> more, smaller topics)
EDGE_FLOOR = 0.30        # ignore kNN edges weaker than this cosine
MEMBERSHIP_TH = 0.52     # min cosine(node, topic centroid) for a HAS_TOPIC edge
TOPK_TOPICS = 3          # max topics a node may belong to
RELATED_TOPK = 6
# Topics are discovered ONLY from aggregate units: projects, collections, and
# LOOSE docs (not inside a collection). Collection MEMBER files would otherwise
# flood discovery (7k maintenance reports → one topic shattered 15×). Members are
# still soft-ASSIGNED to the discovered topics and stay individually searchable.

STOP = set("the a an and or of to for in on with from this that report analysis "
           "data new final v1 v2 1 2 3 doc docs untitled copy report".split())


def load():
    z = np.load(HERE / "vectors.npz", allow_pickle=True)
    ids = list(z["ids"]); ns = list(z["ns"]); vecs = z["vecs"].astype(np.float32)
    nodes = {json.loads(l)["id"]: json.loads(l)
             for l in open(HERE / "nodes.jsonl")}
    return ids, ns, vecs, nodes


# ----------------------------------------------------------------- Louvain (numpy)

def knn_edges(V: np.ndarray, k: int, floor: float):
    """Symmetric weighted edge list from cosine top-k (V is L2-normalized)."""
    n = V.shape[0]
    edges: dict[tuple[int, int], float] = {}
    # process in blocks to bound memory
    B = 512
    for s in range(0, n, B):
        sims = V[s:s + B] @ V.T                       # (b, n) cosine
        for bi, row in enumerate(sims):
            i = s + bi
            row[i] = -1
            idx = np.argpartition(-row, k)[:k]
            for j in idx:
                w = float(row[j])
                if w < floor:
                    continue
                a, b = (i, int(j)) if i < j else (int(j), i)
                if a != b:
                    edges[(a, b)] = max(edges.get((a, b), 0.0), w)
    return edges


def louvain(n: int, edges: dict[tuple[int, int], float], resolution: float):
    """One-level Louvain local-moving (modularity). Pure python/numpy, Swift-portable."""
    adj: list[list[tuple[int, float]]] = [[] for _ in range(n)]
    deg = np.zeros(n)
    m = 0.0
    for (a, b), w in edges.items():
        adj[a].append((b, w)); adj[b].append((a, w))
        deg[a] += w; deg[b] += w; m += w
    if m == 0:
        return list(range(n))
    comm = list(range(n))
    ctot = deg.copy()                                  # sum of degrees in community
    order = list(range(n))
    improved = True
    passes = 0
    while improved and passes < 20:
        improved = False
        passes += 1
        for i in order:
            ci = comm[i]
            ki = deg[i]
            # weight from i to each neighboring community
            wto: dict[int, float] = defaultdict(float)
            for j, w in adj[i]:
                if j != i:
                    wto[comm[j]] += w
            # remove i from its community
            ctot[ci] -= ki
            best_c, best_gain = ci, 0.0
            for c, wic in wto.items():
                gain = wic - resolution * ctot[c] * ki / (2 * m)
                if gain > best_gain:
                    best_gain, best_c = gain, c
            # gain of staying isolated baseline is 0; also consider original ci
            comm[i] = best_c
            ctot[best_c] += ki
            if best_c != ci:
                improved = True
    return comm


# ------------------------------------------------------------------- labeling

def tokens(s: str):
    for t in re.split(r"[^\w　-鿿가-힯]+", (s or "").lower()):
        if len(t) > 1 and t not in STOP and not t.isdigit():
            yield t


def label_topic(member_ids, nodes, V, idx_of, centroid):
    # key terms from member display names
    c = Counter()
    for mid in member_ids:
        nm = Path(nodes[mid]["path"]).stem if mid in nodes else ""
        for t in tokens(nm):
            c[t] += 1
    terms = [t for t, _ in c.most_common(4)]
    # member nearest the centroid → representative title
    best, bs = None, -1
    for mid in member_ids:
        sim = float(V[idx_of[mid]] @ centroid)
        if sim > bs:
            bs, best = sim, mid
    rep = Path(nodes[best]["path"]).stem if best in nodes else "?"
    return (" / ".join(terms) if terms else rep), rep


# ----------------------------------------------------------------------- main

def main():
    ids, ns, vecs, nodes = load()
    res = float(sys.argv[1]) if len(sys.argv) > 1 else RESOLUTION
    th = float(sys.argv[2]) if len(sys.argv) > 2 else MEMBERSHIP_TH

    # Mean-center: bge-m3 is anisotropic (random pairs ~0.5-0.7 cosine). Removing
    # the global common component spreads cosines out and sharpens topics.
    raw = vecs.copy()
    mu = vecs.mean(0)
    vecs = vecs - mu
    vecs /= (np.linalg.norm(vecs, axis=1, keepdims=True) + 1e-9)
    # quick anisotropy readout on a sample
    import numpy.random as _r
    samp = _r.default_rng(0).choice(len(raw), size=min(400, len(raw)), replace=False)
    def medcos(M):
        S = M[samp] @ M[samp].T
        iu = np.triu_indices(len(samp), 1)
        return float(np.median(S[iu]))
    print(f"median pairwise cosine — raw: {medcos(raw):.3f}  centered: {medcos(vecs):.3f}  "
          f"(res={res}, th={th})")

    idx_of = {i: k for k, i in enumerate(ids)}

    def is_rich(k: int) -> bool:
        nd = nodes.get(ids[k], {})
        t = nd.get("type")
        if t in ("project", "collection"):
            return True
        # loose docs only — collection members must not drive discovery
        return t == "file" and ns[k] == "doc" and not nd.get("collection_id")

    rich = [k for k in range(len(ids)) if is_rich(k)]
    # Seed discovery with a CAPPED sample of each collection's members so large
    # domains (e.g. 7k maintenance reports) form their own topic proportionally,
    # without the flood that shattered them before.
    SAMPLE_PER_COLL = 15
    mem_by_coll = defaultdict(list)
    for k, i in enumerate(ids):
        nd = nodes.get(i, {})
        if nd.get("type") == "file" and nd.get("collection_id") and ns[k] in ("doc", "data"):
            mem_by_coll[nd["collection_id"]].append(k)
    for mem in mem_by_coll.values():
        rich += mem[:SAMPLE_PER_COLL]
    rich = sorted(set(rich))
    print(f"vectors: {len(ids)}  | rich (topic-discovery): {len(rich)}  | dim={vecs.shape[1]}")

    Vr = vecs[rich]
    edges = knn_edges(Vr, KNN, EDGE_FLOOR)
    comm = louvain(len(rich), edges, res)

    # group rich nodes into communities (min size 3)
    groups = defaultdict(list)
    for local_i, c in enumerate(comm):
        groups[c].append(ids[rich[local_i]])
    groups = {c: g for c, g in groups.items() if len(g) >= 3}

    # centroids + labels
    topics = []
    centroids = []
    for c, g in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        cen = vecs[[idx_of[i] for i in g]].mean(0)
        cen /= (np.linalg.norm(cen) + 1e-9)
        label, rep = label_topic(g, nodes, vecs, idx_of, cen)
        tid = f"t{len(topics)}"
        topics.append({"id": tid, "label": label, "rep": rep, "size_seed": len(g)})
        centroids.append(cen)
    C = np.asarray(centroids, dtype=np.float32)
    print(f"topics discovered: {len(topics)}")

    # soft membership: every node -> top-k topics above threshold
    has_topic = []
    member_count = Counter()
    if len(topics):
        sims_all = vecs @ C.T                          # (N, T)
        for k, nid in enumerate(ids):
            row = sims_all[k]
            order = np.argsort(-row)[:TOPK_TOPICS]
            for ti in order:
                w = float(row[ti])
                if w >= th:
                    has_topic.append({"node": nid, "topic": topics[ti]["id"], "w": round(w, 3)})
                    member_count[topics[ti]["id"]] += 1

    # RELATED_TO between projects
    proj_idx = [k for k, n in enumerate(ns) if n == "project"]
    related = []
    if proj_idx:
        Vp = vecs[proj_idx]
        sims = Vp @ Vp.T
        for a, ga in enumerate(proj_idx):
            row = sims[a].copy(); row[a] = -1
            for b in np.argsort(-row)[:RELATED_TOPK]:
                w = float(row[b])
                if w >= th:
                    related.append({"src": ids[ga], "dst": ids[proj_idx[b]], "w": round(w, 3)})

    # write
    with open(HERE / "topics.jsonl", "w") as f:
        for t in topics:
            t = dict(t, members=member_count[t["id"]])
            f.write(json.dumps(t, ensure_ascii=False) + "\n")
    with open(HERE / "edges.jsonl", "w") as f:
        for e in has_topic:
            f.write(json.dumps({"type": "HAS_TOPIC", **e}, ensure_ascii=False) + "\n")
        for e in related:
            f.write(json.dumps({"type": "RELATED_TO", **e}, ensure_ascii=False) + "\n")

    report(topics, member_count, nodes, ids, ns, has_topic, related)


def report(topics, member_count, nodes, ids, ns, has_topic, related):
    line = "=" * 66
    print(line); print("STAGE D — TOPICS (Louvain + soft membership)"); print(line)
    by_node = defaultdict(list)
    for e in has_topic:
        by_node[e["node"]].append(e)
    print(f"topics: {len(topics)} | HAS_TOPIC edges: {len(has_topic)} | "
          f"RELATED_TO: {len(related)}")
    print(line)
    name = {t["id"]: t["label"] for t in topics}
    for t in sorted(topics, key=lambda x: -member_count[x["id"]])[:25]:
        print(f"[{member_count[t['id']]:>4} members] {t['label']}")
        print(f"            e.g. {t['rep']}")
    print(line)
    # a few example projects with their weighted topics
    print("sample PROJECT topic memberships:")
    shown = 0
    for k, nid in enumerate(ids):
        if ns[k] != "project":
            continue
        ts = sorted(by_node.get(nid, []), key=lambda e: -e["w"])[:4]
        if not ts:
            continue
        nm = Path(nodes[nid]["path"]).name
        print(f"  {nm:<26} " + ", ".join(f"{e['w']:.2f} {name[e['topic']]}" for e in ts))
        shown += 1
        if shown >= 18:
            break
    print(line)


if __name__ == "__main__":
    main()
