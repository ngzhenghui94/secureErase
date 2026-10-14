import AppKit
import Sparkle
import SwiftUI

@MainActor
final class AppUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdates()
    @Published var activeOperations = 0
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var installing = false
    @Published var quitting = false
    var isBusy: Bool { activeOperations > 0 }
    private var controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?
    private var installationTask: Task<Void, Never>?
    private var installInvoked = false

    func start() {
        guard controller == nil, !CommandLine.arguments.contains("--selftest") else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        updater.sendsSystemProfile = false
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor [weak self] in self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        controller.startUpdater()
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }
    func updater(_ updater: SPUUpdater, mayPerform check: SPUUpdateCheck) throws { try requireManualCheck(check) }
    func requireManualCheck(_ check: SPUUpdateCheck) throws {
        guard check == .updates, !isBusy, !installing, !quitting else {
            throw NSError(domain: "SecureErase.Updates", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Choose Check for Updates… after erasure finishes. Updates are manual only."])
        }
    }
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        postponeInstallation(installHandler)
        return true
    }
    func postponeInstallation(_ installHandler: @escaping () -> Void) {
        guard installationTask == nil else { return }
        installing = true
        installationTask = Task { @MainActor in
            while isBusy {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            }
            guard !Task.isCancelled, !quitting else { return }
            installInvoked = true
            installHandler()
        }
    }
    func cancelInstallation() {
        installationTask?.cancel()
        installationTask = nil
        installInvoked = false
        installing = false
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { cancelInstallation() }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor check: SPUUpdateCheck, error: Error?) {
        if error != nil || !installInvoked { cancelInstallation() }
    }
    static func selfTest() async throws {
        let updates = shared
        try updates.requireManualCheck(.updates)
        do { try updates.requireManualCheck(.updatesInBackground); preconditionFailure("Background check accepted") } catch { }
        updates.activeOperations = 1
        do { try updates.requireManualCheck(.updates); preconditionFailure("Busy check accepted") } catch { }
        var invoked = false
        updates.postponeInstallation { invoked = true }
        precondition(updates.installing && !invoked)
        updates.activeOperations = 0
        await updates.installationTask?.value
        precondition(invoked && updates.installing)
        updates.cancelInstallation()
        updates.quitting = true
        updates.postponeInstallation { preconditionFailure("User quit must not install") }
        await updates.installationTask?.value
        updates.cancelInstallation()
        precondition(updates.quitting && !updates.installing)
        updates.quitting = false
        print("update safety selftest ok: manual checks, busy rejection, drain, quit ownership")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { AppUpdates.shared.start() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let updates = AppUpdates.shared
        guard updates.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Erasure in progress"
        alert.informativeText = "Wait for all erasure operations to finish before quitting. Partially erased files cannot be restored."
        alert.addButton(withTitle: "Quit When Done")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        updates.quitting = true
        Task { @MainActor in
            while updates.isBusy { try? await Task.sleep(for: .milliseconds(150)) }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
