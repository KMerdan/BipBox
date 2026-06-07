// bipbox-harness — a JSON-in / JSON-out driver for the Bipbox workspace.
//
// Usage:
//   echo '{"action":"addFolder","path":"~/Downloads","depth":"top"}' | bipbox-harness
//   printf '%s\n' '{"action":"addFolder","path":"/tmp/x"}' '{"action":"search","query":"pdf"}' | bipbox-harness
//
// Reads one JSON command per line from stdin; prints one JSON snapshot per line.
// Flags:
//   --base <dir>   use a specific data directory (default: fresh temp dir)
//   --pretty       pretty-print each snapshot
import BipboxCore
import BipboxHarness
import BipboxWorkspaceUI
import Foundation

@MainActor
func run() async {
    var baseDir: URL?
    var pretty = false
    var args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--base":
            if i + 1 < args.count { baseDir = URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath, isDirectory: true); i += 1 }
        case "--pretty":
            pretty = true
        default:
            break
        }
        i += 1
    }

    let harness: BipboxHarness
    do {
        harness = try BipboxHarness(baseDirectory: baseDir)
    } catch {
        FileHandle.standardError.write(Data("Failed to start harness: \(error)\n".utf8))
        exit(1)
    }
    await harness.start()

    let encoder = JSONEncoder()
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]

    func emit(_ snapshot: WorkspaceSnapshot) {
        if let data = try? encoder.encode(snapshot), let line = String(data: data, encoding: .utf8) {
            print(line)
            fflush(stdout)
        }
    }

    // Emit the initial snapshot so callers see the starting state.
    emit(await harness.snapshot())

    while let line = readLine(strippingNewline: true) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        if trimmed == "quit" || trimmed == "exit" { break }
        let snapshot = await decodeAndApply(trimmed, harness: harness)
        emit(snapshot)
    }
}

@MainActor
func decodeAndApply(_ line: String, harness: BipboxHarness) async -> WorkspaceSnapshot {
    let decoder = JSONDecoder()
    if let data = line.data(using: .utf8), let command = try? decoder.decode(WorkspaceCommand.self, from: data) {
        return await harness.apply(command)
    }
    return await harness.model.snapshot(error: "Could not parse command: \(line)")
}

await run()
