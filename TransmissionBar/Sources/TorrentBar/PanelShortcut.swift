import AppKit
import SwiftUI
import Carbon

struct PanelShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
    static let standard = PanelShortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥T")
    static func load() -> PanelShortcut {
        guard let data = UserDefaults.standard.data(forKey: "panelShortcut"),
              let shortcut = try? JSONDecoder().decode(PanelShortcut.self, from: data),
              shortcut.keyCode < 128,
              shortcut.modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else { return .standard }
        return shortcut
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: PanelShortcut
    @Binding var capturing: Bool
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(title: shortcut.label, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.target = button; button.action = #selector(RecorderButton.beginRecording)
        button.setAccessibilityLabel("Record panel toggle shortcut")
        button.onRecord = { shortcut = $0 }
        button.onRecordingChanged = { capturing = $0 }
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.shortcutLabel = shortcut.label
        if !button.recording { button.title = shortcut.label }
        button.onRecord = { shortcut = $0 }
        button.onRecordingChanged = { capturing = $0 }
    }
    final class RecorderButton: NSButton {
        var onRecord: ((PanelShortcut) -> Void)?
        var onRecordingChanged: ((Bool) -> Void)?
        var shortcutLabel = "⌃⌥T"
        var recording = false
        override var acceptsFirstResponder: Bool { true }
        @objc func beginRecording() {
            recording = true; onRecordingChanged?(true); title = "Press shortcut…"; window?.makeFirstResponder(self)
        }
        override func resignFirstResponder() -> Bool {
            recording = false; onRecordingChanged?(false); title = shortcutLabel
            return super.resignFirstResponder()
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if recording { keyDown(with: event); return true }
            return super.performKeyEquivalent(with: event)
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == UInt16(kVK_Escape) { recording = false; onRecordingChanged?(false); title = shortcutLabel; return }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard !flags.intersection([.command, .control, .option]).isEmpty,
                  let key = event.charactersIgnoringModifiers?.uppercased(),
                  !key.isEmpty, key.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xF700 }) else {
                title = "Use ⌘, ⌃ or ⌥ + key"; return
            }
            var modifiers: UInt32 = 0
            var label = ""
            if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
            if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
            if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
            label += key == " " ? "Space" : key
            recording = false; shortcutLabel = label; title = label
            onRecord?(PanelShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label))
            onRecordingChanged?(false)
        }
    }
}
