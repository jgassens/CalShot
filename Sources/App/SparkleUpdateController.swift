import AppKit
import Foundation
import Sparkle

@MainActor
final class SparkleUpdateController: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private var updaterController: SPUStandardUpdaterController!
    private var activationPolicyBeforeUpdate: NSApplication.ActivationPolicy?

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    func checkForUpdates() {
        prepareForUpdateUI()
        updaterController.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        prepareForUpdateUI(activating: state.userInitiated)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        NSApp.dockTile.badgeLabel = ""
    }

    func standardUserDriverWillFinishUpdateSession() {
        restoreMenuBarActivationPolicy()
    }

    private func prepareForUpdateUI() {
        prepareForUpdateUI(activating: true)
    }

    private func prepareForUpdateUI(activating: Bool) {
        if activationPolicyBeforeUpdate == nil {
            activationPolicyBeforeUpdate = NSApp.activationPolicy()
        }
        NSApp.setActivationPolicy(.regular)
        if activating {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.dockTile.badgeLabel = "1"
    }

    private func restoreMenuBarActivationPolicy() {
        NSApp.dockTile.badgeLabel = ""
        if let activationPolicyBeforeUpdate {
            NSApp.setActivationPolicy(activationPolicyBeforeUpdate)
            self.activationPolicyBeforeUpdate = nil
        }
    }
}
