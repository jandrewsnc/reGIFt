import AppKit
import Carbon.HIToolbox
import SwiftUI
import ServiceManagement

extension Notification.Name {
    static let reGIFtAPIKeyCleared = Notification.Name("reGIFtAPIKeyCleared")
}

class PreviewState: ObservableObject {
    @Published var gif: KlipyGIF?
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var previewPanel: NSPanel?
    let previewState = PreviewState()

    static let popoverSize    = NSSize(width: 530, height: 460)
    static let previewHeight: CGFloat = 280

    // Incremented whenever a show or instant-hide occurs.
    // Dismiss completion handlers check this to avoid closing a panel that was re-shown.
    private var animationToken = 0

    // Debounce hiding so a quick gap crossing between cells doesn't flash the preview away.
    private var hideTask: DispatchWorkItem?

    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonEventHandlerRef: EventHandlerRef?
    private var shortcutConfigPanel: NSPanel?
    private static let keyCodeKey   = "shortcutKeyCode"
    private static let modifiersKey = "shortcutModifiers"

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        registerLoginItem()
        registerHotkeyIfSaved()
    }

    private func registerLoginItem() {
        // Registers the app as a Login Item so it launches automatically on startup.
        // Silently ignored during development (app must be in /Applications/).
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            }
            button.action = #selector(handleStatusClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    @objc private func handleStatusClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        if #available(macOS 13.0, *) {
            let loginItem = NSMenuItem(
                title: "Open at Login",
                action: #selector(toggleLoginItem),
                keyEquivalent: ""
            )
            loginItem.target = self
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(loginItem)
            menu.addItem(.separator())
        }

        let updateKey = NSMenuItem(title: "Update API Key", action: #selector(resetAPIKey), keyEquivalent: "")
        updateKey.target = self
        menu.addItem(updateKey)

        let shortcutItem = NSMenuItem(title: "Set Shortcut…", action: #selector(openShortcutConfig), keyEquivalent: "")
        shortcutItem.target = self
        menu.addItem(shortcutItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit reGIFt", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        // Show once then clear so left-click still opens the popover
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func resetAPIKey() {
        KeychainHelper.delete()
        NotificationCenter.default.post(name: .reGIFtAPIKeyCleared, object: nil)
        dismissPreviewPanel(animated: false)
        popover.performClose(nil)
        // Reopen to show onboarding immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self.popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func toggleLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = AppDelegate.popoverSize
        popover.behavior = .transient
        popover.delegate = self

        let view = ContentView { [weak self] gif in self?.handleHover(gif) }
        let hosting = NSHostingController(rootView: view)
        // Clear the hosting view's own background so the NSVisualEffectView
        // in SwiftUI composites directly against whatever is behind the window.
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear
        popover.contentViewController = hosting
    }

    // MARK: - Hover handling

    func handleHover(_ gif: KlipyGIF?) {
        previewState.gif = gif

        if gif != nil {
            // Cancel any pending hide and show immediately.
            hideTask?.cancel()
            hideTask = nil
            showPreviewPanel()
        } else {
            // Debounce: wait 80 ms before hiding.
            // This swallows hide events from crossing the 1px gap between cells.
            let task = DispatchWorkItem { [weak self] in
                self?.dismissPreviewPanel(animated: true)
            }
            hideTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: task)
        }
    }

    // MARK: - Preview panel show / hide

    private func showPreviewPanel() {
        guard let popoverWindow = popover.contentViewController?.view.window,
              let contentView = popoverWindow.contentView else { return }

        // Use the content view's actual screen rect — the window frame includes
        // shadow padding which creates a visual gap if used directly.
        let contentScreenRect = popoverWindow.convertToScreen(contentView.frame)
        let h = AppDelegate.previewHeight

        let targetFrame = NSRect(x: contentScreenRect.minX,
                                 y: contentScreenRect.minY - h,
                                 width: contentScreenRect.width,
                                 height: h)

        // Bump token so any in-flight dismiss completion becomes a no-op.
        animationToken += 1

        if let panel = previewPanel {
            // Panel already exists (may be mid-dismiss). Re-animate to full size.
            if !panel.isVisible { panel.orderFront(nil) }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            let panel = buildPreviewPanel()
            self.previewPanel = panel
            let startFrame = NSRect(x: targetFrame.minX, y: contentScreenRect.minY,
                                    width: targetFrame.width, height: 0)
            panel.setFrame(startFrame, display: false)
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        }
    }

    private func dismissPreviewPanel(animated: Bool) {
        guard let panel = previewPanel else { return }

        if !animated {
            animationToken += 1
            panel.orderOut(nil)
            previewPanel = nil
            return
        }

        guard let popoverWindow = popover.contentViewController?.view.window else {
            panel.orderOut(nil)
            previewPanel = nil
            return
        }

        let token = animationToken + 1
        animationToken = token

        let contentScreenRect = popoverWindow.convertToScreen(popoverWindow.contentView?.frame ?? popoverWindow.contentView!.bounds)
        let endFrame = NSRect(x: panel.frame.minX, y: contentScreenRect.minY,
                              width: panel.frame.width, height: 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(endFrame, display: true)
        }, completionHandler: { [weak self, weak panel] in
            guard let self, let panel,
                  self.animationToken == token else { return }
            panel.orderOut(nil)
            if self.previewPanel === panel { self.previewPanel = nil }
        })
    }

    private func buildPreviewPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = NSHostingController(
            rootView: PreviewPanelView().environmentObject(previewState)
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        return panel
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        guard let window = popover.contentViewController?.view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear

        // NSPopover wraps the content in its own "frame view" which draws the
        // solid bubble background. Clearing it lets VisualEffectBackground show through.
        if let frameView = window.contentView?.superview {
            frameView.wantsLayer = true
            frameView.layer?.backgroundColor = .clear
        }
    }

    func popoverWillClose(_ notification: Notification) {
        hideTask?.cancel()
        hideTask = nil
        dismissPreviewPanel(animated: false)
    }

    // MARK: - Global hotkey

    private func registerHotkeyIfSaved() {
        guard UserDefaults.standard.object(forKey: Self.keyCodeKey) != nil else { return }
        let code = UInt16(UserDefaults.standard.integer(forKey: Self.keyCodeKey))
        let mods = NSEvent.ModifierFlags(rawValue: UInt(UserDefaults.standard.integer(forKey: Self.modifiersKey)))
        registerHotkey(keyCode: code, modifiers: mods)
    }

    private func registerHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        if let ref = carbonHotKeyRef { UnregisterEventHotKey(ref); carbonHotKeyRef = nil }
        if let ref = carbonEventHandlerRef { RemoveEventHandler(ref); carbonEventHandlerRef = nil }

        var carbonMods: UInt32 = 0
        if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
        if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }

        var hotKeyID = EventHotKeyID(signature: OSType(0x72474654), id: 1)
        RegisterEventHotKey(UInt32(keyCode), carbonMods, hotKeyID,
                            GetApplicationEventTarget(), 0, &carbonHotKeyRef)

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let ptr = userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { delegate.togglePopover() }
            return noErr
        }, 1, &eventSpec, selfPtr, &carbonEventHandlerRef)
    }

    private func clearHotkey() {
        if let ref = carbonHotKeyRef { UnregisterEventHotKey(ref); carbonHotKeyRef = nil }
        if let ref = carbonEventHandlerRef { RemoveEventHandler(ref); carbonEventHandlerRef = nil }
        UserDefaults.standard.removeObject(forKey: Self.keyCodeKey)
        UserDefaults.standard.removeObject(forKey: Self.modifiersKey)
    }

    @objc private func openShortcutConfig() {
        shortcutConfigPanel?.close()
        registerHotkeyIfSaved()
        let existingCode = (UserDefaults.standard.object(forKey: Self.keyCodeKey) as? Int).map { UInt16($0) }
        let existingMods = (UserDefaults.standard.object(forKey: Self.modifiersKey) as? Int)
            .map { NSEvent.ModifierFlags(rawValue: UInt($0)) }

        let configView = ShortcutConfigView(
            existingCode: existingCode,
            existingMods: existingMods,
            onSave: { [weak self] code, mods in
                guard let self else { return }
                UserDefaults.standard.set(Int(code), forKey: Self.keyCodeKey)
                UserDefaults.standard.set(Int(mods.rawValue), forKey: Self.modifiersKey)
                self.registerHotkey(keyCode: code, modifiers: mods)
                self.shortcutConfigPanel?.close()
                self.shortcutConfigPanel = nil
            },
            onClear: { [weak self] in
                self?.clearHotkey()
            },
            onDismiss: { [weak self] in
                self?.shortcutConfigPanel?.close()
                self?.shortcutConfigPanel = nil
            }
        )

        let controller = NSHostingController(rootView: configView)
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = ""
        panel.contentViewController = controller
        panel.isReleasedWhenClosed = false
        controller.view.layout()
        panel.setContentSize(controller.view.fittingSize)
        panel.center()
        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        shortcutConfigPanel = panel
    }

    // MARK: - Toggle

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            hideTask?.cancel()
            hideTask = nil
            dismissPreviewPanel(animated: false)
            popover.performClose(nil)
        } else {
            previewState.gif = nil
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
