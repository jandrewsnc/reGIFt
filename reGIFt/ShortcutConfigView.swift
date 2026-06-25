import AppKit
import SwiftUI

// MARK: - Key capture field

class KeyCaptureField: NSTextField {
    var onCapture: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    override func keyDown(with event: NSEvent) {
        guard !Self.modifierKeyCodes.contains(event.keyCode) else { return }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        onCapture?(event.keyCode, mods)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !Self.modifierKeyCodes.contains(event.keyCode),
              event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        onCapture?(event.keyCode, mods)
        return true
    }
}

// MARK: - SwiftUI wrapper

struct KeyCaptureView: NSViewRepresentable {
    var displayText: String
    var onCapture: (UInt16, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> KeyCaptureField {
        let field = KeyCaptureField()
        field.onCapture = onCapture
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.alignment = .center
        field.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        field.placeholderString = "Click here, then press keys…"
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ nsView: KeyCaptureField, context: Context) {
        if nsView.stringValue != displayText {
            nsView.stringValue = displayText
        }
    }
}

// MARK: - Shortcut display string

func shortcutDisplayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
    var s = ""
    if modifiers.contains(.control) { s += "⌃" }
    if modifiers.contains(.option)  { s += "⌥" }
    if modifiers.contains(.shift)   { s += "⇧" }
    if modifiers.contains(.command) { s += "⌘" }
    let names: [UInt16: String] = [
        0: "A",  1: "S",  2: "D",  3: "F",  4: "H",  5: "G",  6: "Z",  7: "X",
        8: "C",  9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
       16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
       23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
       30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
       37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
       43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥",
       49: "Space", 50: "`", 51: "⌫", 53: "⎋",
       96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
      103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
      115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
      123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
    s += names[keyCode] ?? "(\(keyCode))"
    return s
}

// MARK: - Config view

struct ShortcutConfigView: View {
    let existingCode: UInt16?
    let existingMods: NSEvent.ModifierFlags?
    let onSave: (UInt16, NSEvent.ModifierFlags) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    @State private var capturedCode: UInt16?
    @State private var capturedMods: NSEvent.ModifierFlags = []
    @State private var displayText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set Shortcut")
                .font(.headline)

            Text("Click the field below, then press your desired key combination.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            KeyCaptureView(displayText: displayText) { code, mods in
                capturedCode = code
                capturedMods = mods
                displayText = shortcutDisplayString(keyCode: code, modifiers: mods)
            }
            .frame(height: 30)

            HStack {
                Button("Clear") {
                    capturedCode = nil
                    capturedMods = []
                    displayText = ""
                    onClear()
                }
                .disabled(existingCode == nil && capturedCode == nil)
                Spacer()
                Button("Cancel") { onDismiss() }
                Button("Save") {
                    guard let code = capturedCode else { return }
                    onSave(code, capturedMods)
                }
                .buttonStyle(.borderedProminent)
                .disabled(capturedCode == nil)
            }

        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            if let code = existingCode, let mods = existingMods {
                capturedCode = code
                capturedMods = mods
                displayText = shortcutDisplayString(keyCode: code, modifiers: mods)
            }
        }
    }
}
