import Carbon
import Foundation
import OSLog

@MainActor
final class GlobalTextHotkeyController {
    private static let signature = fourCharacterCode("CSHT")
    private static let hotKeyID = UInt32(1)
    #if DEBUG
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.local.CalShot", category: "GlobalTextHotkey")
    #endif

    private var eventHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onHotkey: () -> Void

    init(onHotkey: @escaping () -> Void) {
        self.onHotkey = onHotkey
        register()
    }

    deinit {
        if let eventHotKey {
            UnregisterEventHotKey(eventHotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func register() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<GlobalTextHotkeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    #if DEBUG
                    GlobalTextHotkeyController.logger.info("Selected-text hotkey fired")
                    #endif
                    controller.onHotkey()
                }
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard handlerStatus == noErr else {
            fputs("CalShot could not install the selected-text hotkey handler: \(handlerStatus)\n", stderr)
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_C),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKey
        )

        if hotKeyStatus != noErr {
            #if DEBUG
            Self.logger.error("Could not register Control-Option-Command-C; status=\(hotKeyStatus)")
            #endif
            fputs("CalShot could not register Control-Option-Command-C: \(hotKeyStatus)\n", stderr)
        } else {
            #if DEBUG
            Self.logger.info("Registered Control-Option-Command-C selected-text hotkey")
            #endif
        }
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.prefix(4).reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}
