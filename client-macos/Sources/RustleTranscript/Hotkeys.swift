import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts through Carbon's RegisterEventHotKey, which needs no Accessibility permission.
@MainActor
final class Hotkeys {
    struct Shortcut {
        let keyCode: Int
        let modifiers: Int
        let label: String
        let title: String
    }

    static let toggleTranscription = Shortcut(keyCode: kVK_ANSI_T, modifiers: optionKey | cmdKey, label: "⌥⌘T", title: "Iniciar / parar a transcrição")
    static let editCaption = Shortcut(keyCode: kVK_ANSI_E, modifiers: optionKey | cmdKey, label: "⌥⌘E", title: "Posicionar a legenda")
    static let toggleCaption = Shortcut(keyCode: kVK_ANSI_L, modifiers: optionKey | cmdKey, label: "⌥⌘L", title: "Mostrar / ocultar a legenda")
    static let all = [toggleTranscription, editCaption, toggleCaption]

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    func register(_ shortcut: Shortcut, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = UInt32(actions.count + 1)
        actions[id] = action
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers),
                                         EventHotKeyID(signature: OSType(0x5254_5853), id: id), // "RTXS"
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs.append(ref) } else { Log.info("hotkey \(shortcut.label) not registered (\(status))") }
    }

    fileprivate func fire(_ id: UInt32) { actions[id]?() }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            let hotkeys = Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKey.id
            DispatchQueue.main.async { MainActor.assumeIsolated { hotkeys.fire(id) } }
            return noErr
        }, 1, &spec, me, &handler)
    }
}
