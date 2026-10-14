import SwiftUI
import CryptoKit

enum Shredder {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Best-effort logical verification of overwritten data/resource forks before deletion.
    /// SSD remnants, snapshots, backups, copies and filename history may survive.
    /// Folders are processed recursively. Symlinks are removed without touching their target;
    /// sockets, FIFOs and devices are unlinked.
    static func erase(_ url: URL) throws {
        let fm = FileManager.default
        var st = stat()
        guard lstat(url.path, &st) == 0 else { throw posix(url) }
        if st.st_mode & S_IFMT == S_IFDIR {
            for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                try erase(child)
            }
        } else if st.st_mode & S_IFMT == S_IFREG {
            try overwrite(url)
        }
        // Symlinks, sockets, FIFOs and devices hold no file data: just unlink them.
        let anon = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try fm.moveItem(at: url, to: anon)
        try fm.removeItem(at: anon)
    }

    static func overwrite(_ url: URL) throws {
        // Validate before any permission or content change; never follow a symlink.
        let check = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard check >= 0 else { throw posix(url) }
        defer { close(check) }
        let original = try regularSingleLink(check, url)
        if original.st_mode & S_IWUSR == 0 {
            guard fchmod(check, original.st_mode | S_IRUSR | S_IWUSR) == 0 else { throw posix(url) }
        }
        let fd = open(url.path, O_RDWR | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw posix(url) }
        defer { close(fd) }
        let opened = try regularSingleLink(fd, url)
        guard opened.st_dev == original.st_dev && opened.st_ino == original.st_ino else {
            throw Failure(errorDescription: "\(url.lastPathComponent): file changed while opening")
        }
        // Detect absence through the validated descriptor; other errors fail closed.
        let resourceSize = fgetxattr(fd, "com.apple.ResourceFork", nil, 0, 0, 0)
        if resourceSize < 0 && errno != ENOATTR { throw posix(url) }
        var resource: Int32 = -1
        if resourceSize > 0 {
            resource = open(url.path + "/..namedfork/rsrc", O_RDWR | O_NOFOLLOW | O_NONBLOCK)
            guard resource >= 0 else { throw posix(url) }
        }
        defer { if resource >= 0 { close(resource) } }
        if resource >= 0 {
            let fork = try regularSingleLink(resource, url)
            guard fork.st_dev == opened.st_dev && fork.st_ino == opened.st_ino else {
                throw Failure(errorDescription: "\(url.lastPathComponent): resource fork changed while opening")
            }
        }
        var buffer = [UInt8](repeating: 0, count: 1 << 20)
        try overwriteAndVerify(fd, url, &buffer)
        if resource >= 0 { try overwriteAndVerify(resource, url, &buffer) }
        // Both forks must pass logical verification before either is truncated.
        guard ftruncate(fd, 0) == 0 else { throw posix(url) }
        if resource >= 0 {
            guard ftruncate(resource, 0) == 0 else { throw posix(url) }
            guard fcntl(resource, F_FULLFSYNC) == 0 else { throw posix(url) }
        }
        guard fcntl(fd, F_FULLFSYNC) == 0 else { throw posix(url) }
    }

    private static func regularSingleLink(_ fd: Int32, _ url: URL) throws -> stat {
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw posix(url) }
        guard st.st_mode & S_IFMT == S_IFREG else {
            throw Failure(errorDescription: "\(url.lastPathComponent): refusing non-regular file")
        }
        guard st.st_nlink == 1 else {
            throw Failure(errorDescription: "\(url.lastPathComponent): refusing multiple hard links to preserve unselected files")
        }
        return st
    }

    private static func overwriteAndVerify(_ fd: Int32, _ url: URL, _ buffer: inout [UInt8]) throws {
        let size = try regularSingleLink(fd, url).st_size
        var expected = SHA256()
        var offset: off_t = 0
        while offset < size {
            let count = Int(min(size - offset, off_t(buffer.count)))
            buffer.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, count) }
            try buffer.withUnsafeBytes { bytes in
                var written = 0
                while written < count {
                    let n = pwrite(fd, bytes.baseAddress!.advanced(by: written), count - written, offset + off_t(written))
                    if n < 0 && errno == EINTR { continue }
                    guard n > 0 else { throw posix(url) }
                    written += n
                }
                expected.update(bufferPointer: UnsafeRawBufferPointer(rebasing: bytes[..<count]))
            }
            offset += off_t(count)
        }
        // Flush requested writes. Read-back checks logical bytes, NOT physical media remnants.
        guard fcntl(fd, F_FULLFSYNC) == 0 else { throw posix(url) }
        var actual = SHA256()
        offset = 0
        while offset < size {
            let count = Int(min(size - offset, off_t(buffer.count)))
            let n = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress!, count, offset) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw Failure(errorDescription: "\(url.lastPathComponent): logical read-back failed") }
            buffer.withUnsafeBytes { actual.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<n])) }
            offset += off_t(n)
        }
        let final = try regularSingleLink(fd, url)
        guard final.st_size == size && expected.finalize() == actual.finalize() else {
            throw Failure(errorDescription: "\(url.lastPathComponent): logical read-back mismatch; not deleting")
        }
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


}

struct ContentView: View {
    @State private var items: [URL] = []
    @State private var log: [String] = []
    @ObservedObject private var updates = AppUpdates.shared
    @State private var busy = false
    @State private var confirm = false
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .confirmationDialog("Best-effort erase ^[\(items.count) item](inflect: true)?", isPresented: $confirm) {
            Button("Overwrite and Delete", role: .destructive) { run() }
        } message: {
            Text("Selected regular files have their data and resource forks overwritten, flushed and logically read back before deletion. Symlinks are deleted without following targets; hardlinked and special files are refused. SSD remnants, snapshots, backups and copies can remain, even with FileVault. Failures may leave partially erased files. This operation cannot be undone.")
        }
    }

    private func add(_ urls: [URL]) {
        guard !busy, !updates.installing, !updates.quitting else { return }
        for u in urls where u.isFileURL && !items.contains(u) {
            if Shredder.isForbidden(u) {
                log.append("Refused: \(u.path)")
            } else {
                items.append(u)
            }
        }
    }

    private func run() {
        guard !busy, !updates.installing, !updates.quitting, !items.isEmpty else { return }
        updates.activeOperations += 1
        let targets = items
        busy = true
        Task.detached {
            for u in targets {
                let msg: String
                do {
                    try Shredder.erase(u)
                    msg = "✓ Logically deleted: \(u.path) — remnants and other copies may remain"
                } catch {
                    msg = "✗ \(u.path) — \(error.localizedDescription). Partial erasure may have occurred."
                }
                await MainActor.run {
                    log.append(msg)
                    items.removeAll { $0 == u }
                }
            }
            await MainActor.run { busy = false; updates.activeOperations -= 1 }
        }
    }
}

struct EraserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var updates = AppUpdates.shared
    var body: some Scene {
        WindowGroup("Secure Erase") { ContentView() }
            .commands {
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates || updates.isBusy || updates.installing || updates.quitting)
                }
            }
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

    // Boundary sizes and a resource-only file exercise both logical forks.
    for size in [0, 1, (1 << 20) - 1, 1 << 20, (1 << 20) + 1, (3 << 20) + 17] {
        let file = root.appendingPathComponent("probe-\(size)")
        try! Data(repeating: 0x42, count: size).write(to: file)
        let fork = URL(fileURLWithPath: file.path + "/..namedfork/rsrc")
        try! Data(repeating: 0x52, count: (1 << 20) + 7).write(to: fork)
        try! Shredder.overwrite(file)
        precondition((try! Data(contentsOf: file)).isEmpty, "data fork must be truncated")
        precondition((try! Data(contentsOf: fork)).isEmpty, "resource fork must be truncated")
    }
    func mustRefuse(_ file: URL) {
        do {
            try Shredder.overwrite(file)
            preconditionFailure("unsafe overwrite accepted: \(file.path)")
        } catch { }
    }
    // A direct overwrite of a link must not chmod or overwrite its destination.
    chmod(outside.path, S_IRUSR)
    mustRefuse(root.appendingPathComponent("link"))
    var outsideStat = stat()
    precondition(lstat(outside.path, &outsideStat) == 0)
    precondition(outsideStat.st_mode & 0o777 == S_IRUSR, "symlink target permissions changed")
    precondition((try! Data(contentsOf: outside)) == Data("keep".utf8))
    let hard = root.appendingPathComponent("hard")
    precondition(link(outside.path, hard.path) == 0)
    mustRefuse(hard)
    do {
        try Shredder.erase(hard)
        preconditionFailure("hardlinked erase accepted")
    } catch { }
    precondition(lstat(outside.path, &outsideStat) == 0)
    precondition(outsideStat.st_mode & 0o777 == S_IRUSR, "hardlink permissions changed")
    precondition((try! Data(contentsOf: hard)) == Data("keep".utf8), "hardlink bytes changed")
    try! fm.removeItem(at: hard)
    let fifo = root.appendingPathComponent("fifo")
    precondition(mkfifo(fifo.path, S_IRUSR | S_IWUSR) == 0)
    mustRefuse(fifo)
    // erase() must unlink non-regular entries (e.g. git's fsmonitor socket) instead of aborting.

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
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--selftest") {
            selfTest()
            do { try await AppUpdates.selfTest() } catch { fatalError(error.localizedDescription) }
            return
        }
        EraserApp.main()
    }
}
