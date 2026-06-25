import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - SwiftUI cell wrapper

struct GIFCellView: View {
    let gif: KlipyGIF
    @Binding var hoveredGIF: KlipyGIF?
    @State private var isHovered = false

    var body: some View {
        DraggableGIFContainer(gif: gif)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.55 : 0), lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0), radius: 6, x: 0, y: 3)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .onHover { hovered in
                isHovered = hovered
                hoveredGIF = hovered ? gif : nil
            }
            .onAppear { prefetch() }
    }

    private func prefetch() {
        guard let url = gif.gifURL else { return }
        let id = gif.id
        Task { try? await GIFCache.shared.cachedFile(id: id, sourceURL: url) }
    }
}

// MARK: - NSViewRepresentable bridge

struct DraggableGIFContainer: NSViewRepresentable {
    let gif: KlipyGIF

    func makeNSView(context: Context) -> DraggableGIFNSView {
        DraggableGIFNSView()
    }

    func updateNSView(_ nsView: DraggableGIFNSView, context: Context) {
        nsView.gif = gif
        if let url = gif.thumbURL ?? gif.gifURL {
            nsView.loadGIF(url: url)
        }
    }
}

// MARK: - AppKit view with WebView display + drag overlay

class DraggableGIFNSView: NSView {
    var gif: KlipyGIF? { didSet { dragOverlay.gif = gif } }
    private var webView: WKWebView!
    private var dragOverlay: DragOverlayView!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        // Transparent overlay sits on top of the WKWebView so drag events reach us
        // instead of being consumed by the web view's internal event handling.
        dragOverlay = DragOverlayView()
        dragOverlay.translatesAutoresizingMaskIntoConstraints = false
        dragOverlay.onMouseDragged = { [weak self] event in self?.handleDrag(event: event) }
        addSubview(dragOverlay)

        let views: [String: NSView] = ["web": webView, "drag": dragOverlay]
        for v in ["web", "drag"] {
            addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[\(v)]|", metrics: nil, views: views))
            addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[\(v)]|", metrics: nil, views: views))
        }
    }

    func loadGIF(url: URL) {
        let escaped = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        webView.loadHTMLString("""
        <html><body style="margin:0;padding:0;background:transparent;overflow:hidden">
        <img src="\(escaped)" style="width:100%;height:100%;object-fit:cover;display:block">
        </body></html>
        """, baseURL: nil)
    }

    private func handleDrag(event: NSEvent) {
        guard let gif = gif else { return }

        // Require the file to already be cached so we never block the main thread.
        // prefetch() in GIFCellView.onAppear ensures it's ready before a user can drag.
        let fileURL = GIFCache.shared.expectedPath(id: gif.id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)

        // Use first frame of the cached GIF as drag thumbnail
        let dragSize = NSSize(width: 120, height: 90)
        let dragImage = NSImage(contentsOf: fileURL) ?? NSImage(size: dragSize)
        dragImage.size = dragSize
        draggingItem.setDraggingFrame(NSRect(origin: .zero, size: dragSize), contents: dragImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

extension DraggableGIFNSView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

// MARK: - WKWebView wrapper for animated GIF display (used by cells and the enlarged preview)

struct GIFWebView: NSViewRepresentable {
    let url: URL?
    var fit: String = "cover"

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url else { return }
        let escaped = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        webView.loadHTMLString("""
        <html><body style="margin:0;padding:0;background:transparent;overflow:hidden">
        <img src="\(escaped)" style="width:100%;height:100%;object-fit:\(fit);display:block">
        </body></html>
        """, baseURL: nil)
    }
}

// MARK: - Transparent overlay that intercepts drag events and owns the context menu

class DragOverlayView: NSView {
    var gif: KlipyGIF?
    var onMouseDragged: ((NSEvent) -> Void)?

    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {}

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let gif else { return nil }
        let menu = NSMenu()
        if gif.klipyPageURL != nil {
            let open = NSMenuItem(title: "View on Klipy", action: #selector(openOnKlipy), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            let copy = NSMenuItem(title: "Copy Image URL", action: #selector(copyImageURL), keyEquivalent: "")
            copy.target = self
            menu.addItem(copy)
        }
        return menu.items.isEmpty ? nil : menu
    }

    @objc private func openOnKlipy() {
        guard let url = gif?.klipyPageURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyImageURL() {
        guard let url = gif?.gifURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    // Accept mouseDown so we receive the subsequent mouseDragged
    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    // Pass scroll events up so the parent ScrollView handles them
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
