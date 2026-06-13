import Foundation

// Argv-driven probe: exercises the real MLXTextEmbedder with whatever strings you
// pass. Verifies dim (expect 1024; 16384 => DWQ pooling bug) and prints pairwise
// cosines (e.g. pass an EN + JP pair of the same concept to check cross-lingual).
//
//   swift run mlx-spike "energy diagnosis report" "省エネ診断報告書" "git worktree cli"

func cosine(_ a: [Float], _ b: [Float]) -> Float {
    var dot: Float = 0, na: Float = 0, nb: Float = 0
    for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
    return dot / (na.squareRoot() * nb.squareRoot() + 1e-9)
}

let texts = Array(CommandLine.arguments.dropFirst())
guard !texts.isEmpty else {
    print("usage: swift run mlx-spike <text> [<text> ...]")
    exit(1)
}

let embedder = MLXTextEmbedder()
print("model: \(await embedder.modelID)")

var vecs: [[Float]] = []
for t in texts {
    if let v = await embedder.embed(t) {
        vecs.append(v)
        print("  dim=\(v.count)  \"\(t.prefix(48))\"")
    } else {
        print("  FAILED  \"\(t.prefix(48))\"")
    }
}

if vecs.count >= 2 {
    print("pairwise cosine:")
    for i in 0..<vecs.count {
        for j in (i + 1)..<vecs.count where vecs[i].count == vecs[j].count {
            print(String(format: "  [%d,%d] = %.3f", i, j, cosine(vecs[i], vecs[j])))
        }
    }
}
