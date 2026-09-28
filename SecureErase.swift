import SwiftUI

enum Shredder {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Overwrites file contents with random data, flushes to disk, anonymises the name, then unlinks.
    /// Folders are processed recursively. Symlinks are removed without touching their target.
    static func erase(_ url: URL) throws {
        let fm = FileManager.default
        let v = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if v.isSymbolicLink != true {
            if v.isDirectory == true {
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    try erase(child)
                }
            } else {
                try overwrite(url)
            }
        }
        // Rename first so the original filename doesn't linger in directory metadata.
        let anon = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try fm.moveItem(at: url, to: anon)
        try fm.removeItem(at: anon)
    }

    static func overwrite(_ url: URL) throws {
        chmod(url.path, S_IRUSR | S_IWUSR)  // read-only files are still ours to destroy
        let fd = open(url.path, O_WRONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw posix(url) }
        defer { close(fd) }

        var st = stat()
        guard fstat(fd, &st) == 0 else { throw posix(url) }
        let size = Int(st.st_size)
        var buf = [UInt8](repeating: 0, count: 1 << 20)
        var off = 0
        while off < size {
            let n = min(size - off, buf.count)
            arc4random_buf(&buf, n)
            let w = buf.withUnsafeBytes { pwrite(fd, $0.baseAddress, n, off_t(off)) }
            guard w > 0 else { throw posix(url) }
            off += w
        }
        // F_FULLFSYNC forces the drive to commit its cache, plain fsync doesn't on macOS.
        guard fcntl(fd, F_FULLFSYNC) == 0 else { throw posix(url) }
        guard ftruncate(fd, 0) == 0 else { throw posix(url) }
    }

    static func posix(_ url: URL) -> Failure {
        Failure(errorDescription: "\(url.lastPathComponent): \(String(cString: strerror(errno)))")
    }

    /// Refuse targets that are almost certainly a mistake.
    static func isForbidden(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        let isVolume = (try? url.resourceValues(forKeys: [.isVolumeKey]).isVolume) ?? false
        return p == "/" || p == NSHomeDirectory() || isVolume == true
    }

    static var fileVaultOn: Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        p.arguments = ["isactive"]
        p.standardOutput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

struct ContentView: View {
    @State private var items: [URL] = []
    @State private var log: [String] = []
    @State private var busy = false
    @State private var confirm = false
    @State private var targeted = false
    private let fileVaultOn = Shredder.fileVaultOn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !fileVaultOn {
                Label("FileVault is off. On SSDs, overwriting can't guarantee old blocks are gone — turn on FileVault for real protection.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(targeted ? Color.red : Color.secondary)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "flame").font(.largeTitle)
                        Text("Drop files or folders here")
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(minHeight: 140, maxHeight: .infinity)
                .dropDestination(for: URL.self) { urls, _ in
                    add(urls)
                    return true
                } isTargeted: { targeted = $0 }

            if !items.isEmpty {
                List {
                    ForEach(items, id: \.self) { u in
                        Label(u.lastPathComponent, systemImage: u.hasDirectoryPath ? "folder" : "doc")
                            .help(u.path)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: 100, maxHeight: 220)

                HStack {
                    Button("Clear") { items.removeAll() }.disabled(busy)
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Button("Erase ^[\(items.count) item](inflect: true)…", role: .destructive) { confirm = true }
                        .disabled(busy)
                        .keyboardShortcut(.defaultAction)
                }
            }

            if !log.isEmpty {
                ScrollView {
                    Text(log.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 90)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 320)
        .confirmationDialog("Permanently erase ^[\(items.count) item](inflect: true)?", isPresented: $confirm) {
            Button("Erase Forever", role: .destructive) { run() }
        } message: {
            Text("Contents are overwritten and deleted. This cannot be undone.")
        }
    }

    private func add(_ urls: [URL]) {
        for u in urls where u.isFileURL && !items.contains(u) {
            if Shredder.isForbidden(u) {
                log.append("Refused: \(u.path)")
            } else {
                items.append(u)
            }
        }
    }

    private func run() {
        let targets = items
        busy = true
        Task.detached {
            for u in targets {
                let msg: String
                do {
                    try Shredder.erase(u)
                    msg = "✓ \(u.path)"
                } catch {
                    msg = "✗ \(u.path) — \(error.localizedDescription)"
                }
                await MainActor.run {
                    log.append(msg)
                    items.removeAll { $0 == u }
                }
            }
            await MainActor.run { busy = false }
        }
    }
}

struct EraserApp: App {
    var body: some Scene {
        WindowGroup("Secure Erase") { ContentView() }
    }
}

func selfTest() {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("se-test-\(UUID().uuidString)")
    let outside = fm.temporaryDirectory.appendingPathComponent("se-keep-\(UUID().uuidString)")
    try! fm.createDirectory(at: root.appendingPathComponent("sub/.hidden"), withIntermediateDirectories: true)
    try! Data(repeating: 0x41, count: 3 << 20).write(to: root.appendingPathComponent("sub/big.bin"))
    try! Data("secret".utf8).write(to: root.appendingPathComponent("sub/.hidden/a.txt"))
    try! Data("keep".utf8).write(to: outside)
    try! fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
    let ro = root.appendingPathComponent("readonly.txt")
    try! Data("ro".utf8).write(to: ro)
    chmod(ro.path, S_IRUSR)

    let probe = fm.temporaryDirectory.appendingPathComponent("se-probe-\(UUID().uuidString)")
    try! Data(repeating: 0x41, count: 4096).write(to: probe)
    try! Shredder.overwrite(probe)
    precondition((try! fm.attributesOfItem(atPath: probe.path)[.size] as! Int) == 0, "file should be truncated")
    try! fm.removeItem(at: probe)

    try! Shredder.erase(root)
    precondition(!fm.fileExists(atPath: root.path), "root should be gone")
    precondition((try? String(contentsOf: outside, encoding: .utf8)) == "keep", "symlink target must survive")
    precondition(Shredder.isForbidden(URL(fileURLWithPath: "/")))
    precondition(Shredder.isForbidden(URL(fileURLWithPath: NSHomeDirectory())))
    try! fm.removeItem(at: outside)
    print("selftest ok")
}

@main
struct Main {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            selfTest()
            return
        }
        EraserApp.main()
    }
}
