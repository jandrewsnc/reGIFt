import AppKit
import SwiftUI
import ServiceManagement

class PreviewState: ObservableObject {
    @Published var gif: KlipyGIF?
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var previewPanel: NSPanel?
    let previewState = PreviewState()

    static let popoverSize    = NSSize(width: 480, height: 460)
    static let previewHeight: CGFloat = 280

    // Incremented whenever a show or instant-hide occurs.
    // Dismiss completion handlers check this to avoid closing a panel that was re-shown.
    private var animationToken = 0

    // Debounce hiding so a quick gap crossing between cells doesn't flash the preview away.
    private var hideTask: DispatchWorkItem?

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        registerLoginItem()
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

        menu.addItem(NSMenuItem(
            title: "Quit reGIFt",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        // Show once then clear so left-click still opens the popover
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
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
        guard let popoverWindow = popover.contentViewController?.view.window else { return }

        let popoverFrame = popoverWindow.frame
        let h = AppDelegate.previewHeight
        // +1 so the panel's top edge overlaps the popover's bottom by 1 pt,
        // sealing any gap that would otherwise show between the two windows.
        let targetFrame = NSRect(x: popoverFrame.minX,
                                 y: popoverFrame.minY - h + 1,
                                 width: popoverFrame.width,
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
            // Start at zero height sitting at the overlap point
            let startFrame = NSRect(x: targetFrame.minX, y: popoverFrame.minY + 1,
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

        let endFrame = NSRect(x: panel.frame.minX, y: popoverWindow.frame.minY,
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
