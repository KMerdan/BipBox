#!/usr/bin/env python3
"""Export the exact 'rich' vector subset cluster.py feeds to Louvain, as JSON,
so the Swift TopicDiscovery port can run on identical input (parity check)."""
import json
from collections import defaultdict
from pathlib import Path

import numpy as np

HERE = Path(__file__).parent

z = np.load(HERE / "vectors.npz", allow_pickle=True)
ids = list(z["ids"]); ns = list(z["ns"]); vecs = z["vecs"].astype(np.float32)
nodes = {json.loads(l)["id"]: json.loads(l) for l in open(HERE / "nodes.jsonl")}

def is_rich(k: int) -> bool:
    nd = nodes.get(ids[k], {})
    t = nd.get("type")
    if t in ("project", "collection"):
        return True
    return t == "file" and ns[k] == "doc" and not nd.get("collection_id")

rich = [k for k in range(len(ids)) if is_rich(k)]
SAMPLE_PER_COLL = 15
mem_by_coll = defaultdict(list)
for k, i in enumerate(ids):
    nd = nodes.get(i, {})
    if nd.get("type") == "file" and nd.get("collection_id") and ns[k] in ("doc", "data"):
        mem_by_coll[nd["collection_id"]].append(k)
for mem in mem_by_coll.values():
    rich += mem[:SAMPLE_PER_COLL]
rich = sorted(set(rich))

out = []
for k in rich:
    name = Path(nodes[ids[k]]["path"]).name if ids[k] in nodes else str(ids[k])
    # NOTE: RAW vectors — Swift does its own mean-centering (of this subset).
    out.append({"name": name, "vector": [round(float(x), 6) for x in vecs[k]]})

with open(HERE / "rich_vectors.json", "w") as f:
    json.dump(out, f, ensure_ascii=False)
print(f"exported {len(out)} rich vectors, dim={vecs.shape[1]}")
