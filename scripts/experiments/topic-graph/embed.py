#!/usr/bin/env python3
"""
Stage C — embed via Ollama HTTP (portable: app calls the SAME endpoint).

  - tier-2 dedup: identical embed_input strings are embedded ONCE (collapses the
    light json/yaml "keys: ..." records that survived byte-fp dedup).
  - batched, defensive (splits a failing batch down to singletons, skips offenders).
  - L2-normalized float32 vectors so dot product == cosine.

Output: vectors.npz {ids, ns, vecs}. Namespaces: project (incl. collections),
doc, data. meta-only nodes are skipped (by-type lane, not topic-embedded).
"""
from __future__ import annotations

import json
import sys
import time
import urllib.request
from pathlib import Path

import numpy as np

HERE = Path(__file__).parent
MODEL = sys.argv[1] if len(sys.argv) > 1 else "qwen3-embedding"
URL = "http://localhost:11434/api/embed"
CHAR_CAP = 2500          # conservative: stay well under the 8192-token ctx even for CJK
BATCH = 8
EMBED_NS = {"project", "doc", "data"}


def embed_batch(texts: list[str]) -> list[list[float]] | None:
    data = json.dumps({"model": MODEL, "input": texts}).encode()
    req = urllib.request.Request(URL, data=data, headers={"Content-Type": "application/json"})
    try:
        r = json.loads(urllib.request.urlopen(req, timeout=60).read())
        return r.get("embeddings") or [r.get("embedding")]
    except Exception:
        return None


def embed_safe(texts: list[str]) -> list[list[float] | None]:
    """Embed a batch; on failure split-and-retry down to singletons, skip dead ones."""
    out = embed_batch(texts)
    if out is not None and len(out) == len(texts):
        return out
    if len(texts) == 1:
        return [None]
    mid = len(texts) // 2
    return embed_safe(texts[:mid]) + embed_safe(texts[mid:])


def main():
    recs = [json.loads(l) for l in open(HERE / "extract.jsonl") if l.strip()]
    work = [r for r in recs
            if r.get("namespace") in EMBED_NS and (r.get("embed_input") or "").strip()
            and len(r["embed_input"].strip()) >= 12]

    # tier-2 dedup: unique embed_input strings (capped)
    uniq: dict[str, None] = {}
    for r in work:
        uniq[r["embed_input"][:CHAR_CAP]] = None
    keys = list(uniq.keys())
    print(f"embeddable nodes: {len(work)}  |  unique strings: {len(keys)}  "
          f"(tier-2 dedup saved {len(work)-len(keys)})", flush=True)

    vec_by_text: dict[str, list[float]] = {}
    t0 = time.time()
    for i in range(0, len(keys), BATCH):
        chunk = keys[i:i + BATCH]
        embs = embed_safe(chunk)
        for k, e in zip(chunk, embs):
            if e is not None:
                vec_by_text[k] = e
        done = min(i + BATCH, len(keys))
        if (i // BATCH) % 25 == 0 or done == len(keys):
            rate = done / max(time.time() - t0, 1e-6)
            eta = (len(keys) - done) / max(rate, 1e-6)
            print(f"  embedded {done}/{len(keys)}  ({rate:.0f}/s, ETA {eta/60:.1f}m)", flush=True)

    ids, ns, vecs = [], [], []
    skipped = 0
    for r in work:
        v = vec_by_text.get(r["embed_input"][:CHAR_CAP])
        if v is None:
            skipped += 1
            continue
        ids.append(r["id"])
        ns.append(r["namespace"])
        vecs.append(v)

    arr = np.asarray(vecs, dtype=np.float32)
    arr /= (np.linalg.norm(arr, axis=1, keepdims=True) + 1e-9)  # L2 normalize
    np.savez(HERE / "vectors.npz",
             ids=np.array(ids, dtype=object), ns=np.array(ns, dtype=object), vecs=arr)
    print(f"\nsaved vectors.npz: {arr.shape[0]} vectors, dim={arr.shape[1]}, "
          f"skipped={skipped}, {time.time()-t0:.0f}s total", flush=True)
    byns = {n: ns.count(n) for n in set(ns)}
    print("by namespace:", byns, flush=True)


if __name__ == "__main__":
    main()
