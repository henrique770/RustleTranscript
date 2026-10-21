import AppKit
import AVFoundation
import Combine
import CoreText
import SwiftUI

/// Wires the app together: the hub window, the caption overlay, the menu-bar item, the global
/// shortcuts, permissions, and the transcription behind the actions the window triggers.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var window: NSWindow?
    private var statusItem: NSStatusItem!
    private lazy var transcription = TranscriptionController(model: model)
    private var overlay: CaptionOverlay!
    private let hotkeys = Hotkeys()
    private var permissionTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var toggleItem: NSMenuItem?
    private var captionItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("RustleTranscript started (bundle=\(Bundle.main.bundlePath))")
        Fonts.register()
        NSApp.setActivationPolicy(.regular)
        overlay = CaptionOverlay(model: model)
        buildMainMenu()
        buildStatusItem()
        wireActions()

        hotkeys.register(Hotkeys.toggleTranscription) { [weak self] in self?.transcription.toggle() }
        hotkeys.register(Hotkeys.editCaption) { [weak self] in self?.overlay.toggleEditing() }
        hotkeys.register(Hotkeys.toggleCaption) { [weak self] in self?.model.settings.showOverlay.toggle() }

        refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        model.$activeSessionID.combineLatest(model.$settings).sink { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshMenu() } }
        }.store(in: &cancellables)
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    /// Closing the window keeps the captions running; quit from the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        if model.isRunning { model.endSession() }
        model.saveNow()
        Thread.sleep(forTimeInterval: 0.2) // let the background write land
    }

    // MARK: - Window & menus

    @objc private func showMainWindow() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.title = "Rustle Transcript"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(red: 0xF5 / 255.0, green: 0xF4 / 255.0, blue: 0xF0 / 255.0, alpha: 1)
            // The hub is always the light sand UI, so native controls must not switch to dark.
            w.appearance = NSAppearance(named: .aqua)
            w.contentViewController = NSHostingController(rootView: MainView(model: model))
            w.setContentSize(NSSize(width: 1120, height: 760))
            w.minSize = NSSize(width: 920, height: 620)
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("RustleTranscriptHub")
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A regular app needs an Edit menu, or Cmd+C / Cmd+V do nothing in its own text fields.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Sobre o Rustle Transcript", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ocultar Rustle Transcript", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Sair do Rustle Transcript", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Editar")
        edit.addItem(withTitle: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Refazer", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Selecionar Tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Janela")
        windowMenu.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Fechar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "Rustle Transcript"
        let menu = NSMenu()
        menu.addItem(item("Abrir Rustle Transcript", #selector(showMainWindow)))
        menu.addItem(.separator())
        let toggle = item("Iniciar transcrição", #selector(toggleTranscription))
        menu.addItem(toggle)
        toggleItem = toggle
        let caption = item("Ocultar legenda", #selector(toggleCaption))
        menu.addItem(caption)
        captionItem = caption
        menu.addItem(item("Posicionar legenda", #selector(editCaption)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair do Rustle Transcript", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        refreshMenu()
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func refreshMenu() {
        let running = model.isRunning
        toggleItem?.title = running ? "Parar transcrição  ⌥⌘T" : "Iniciar transcrição  ⌥⌘T"
        captionItem?.title = model.settings.showOverlay ? "Ocultar legenda  ⌥⌘L" : "Mostrar legenda  ⌥⌘L"
        statusItem.button?.image = NSImage(systemSymbolName: running ? "captions.bubble.fill" : "captions.bubble",
                                           accessibilityDescription: "Rustle Transcript")
    }

    @objc private func toggleTranscription() { transcription.toggle() }
    @objc private func toggleCaption() { model.settings.showOverlay.toggle() }
    @objc private func editCaption() { overlay.setEditing(true) }

    private func wireActions() {
        model.start = { [weak self] in
            guard let self else { return }
            if self.model.settings.captureMic && !self.model.permissions.microphone {
                self.requestPermissions()
                if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized { return }
            }
            self.transcription.start()
        }
        model.stop = { [weak self] in self?.transcription.stop() }
        model.toggleEditOverlay = { [weak self] in self?.overlay.toggleEditing() }
        model.resetOverlayPosition = { [weak self] in self?.overlay.resetPosition() }
        model.requestPermissions = { [weak self] in self?.requestPermissions() }
    }

    // MARK: - Permissions

    private func refreshPermissions() {
        let p = AppModel.Permissions(microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        if p != model.permissions { model.permissions = p }
    }

    /// Asks for the microphone if undecided; if it was refused, opens System Settings.
    /// System audio has no status API: macOS asks the first time the tap starts.
    private func requestPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in Log.info("microphone access: \(granted)") }
        case .denied, .restricted:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        default: break
        }
    }
}

/// Figtree and EB Garamond: registered from the app bundle (also listed in ATSApplicationFontsPath),
/// or from the source checkout when the binary runs outside the .app (snapshots, `swift run`).
enum Fonts {
    static func register() {
        var dirs: [URL] = []
        if let res = Bundle.main.resourceURL { dirs.append(res.appendingPathComponent("Fonts")) }
        dirs.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Fonts"))
        guard NSFont(name: "Figtree", size: 12) == nil else { return }
        for dir in dirs {
            let fonts = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "ttf" } ?? []
            guard !fonts.isEmpty else { continue }
            for url in fonts { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
            return
        }
    }
}
