import AppKit
import TorrentCore

/// Owns the folder button's target for the lifetime of this modal confirmation.
/// Nothing is submitted to the daemon until Add is pressed.
@MainActor
final class AddTorrentDialog: NSObject {
    private let destination = NSTextField(string: "")
    private let start = NSButton(checkboxWithTitle: "Start transfers after adding", target: nil, action: nil)
    private let priority = NSPopUpButton(frame: .zero, pullsDown: false)

    func confirm(names: [String], defaults: [String: Any]) -> TorrentAddOptions? {
        let alert = NSAlert()
        alert.messageText = names.count == 1 ? "Add torrent" : "Add \(names.count) torrents"
        alert.informativeText = "Choose settings before adding. These options apply to every torrent listed below."
        alert.addButton(withTitle: names.count == 1 ? "Add" : "Add All")
        alert.addButton(withTitle: "Cancel")
        let content = NSStackView()
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        content.widthAnchor.constraint(equalToConstant: 440).isActive = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let list = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 80))
        list.isEditable = false; list.isSelectable = true
        list.isHorizontallyResizable = false; list.isVerticallyResizable = true
        list.textContainer?.widthTracksTextView = true
        list.autoresizingMask = [.width]
        list.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        list.string = names.joined(separator: "\n")
        scroll.documentView = list
        scroll.heightAnchor.constraint(equalToConstant: 80).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 440).isActive = true
        content.addArrangedSubview(scroll)
        content.addArrangedSubview(NSTextField(labelWithString: "Download folder"))
        destination.stringValue = defaults["download_dir"] as? String ?? ""
        destination.placeholderString = "/path/to/downloads"
        destination.setAccessibilityLabel("Download folder")
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        let folderRow = NSStackView(views: [destination, choose])
        folderRow.orientation = .horizontal; folderRow.spacing = 8
        folderRow.widthAnchor.constraint(equalToConstant: 440).isActive = true
        content.addArrangedSubview(folderRow)
        start.state = (defaults["start_added_torrents"] as? Bool ?? true) ? .on : .off
        content.addArrangedSubview(start)
        priority.addItems(withTitles: ["Low", "Normal", "High"]); priority.selectItem(at: 1)
        priority.setAccessibilityLabel("Transfer priority")
        let priorityRow = NSStackView(views: [NSTextField(labelWithString: "Priority"), priority])
        priorityRow.spacing = 12
        content.addArrangedSubview(priorityRow)
        alert.accessoryView = content
        content.layoutSubtreeIfNeeded()
        content.setFrameSize(content.fittingSize)
        alert.window.initialFirstResponder = destination

        while alert.runModal() == .alertFirstButtonReturn {
            let path = (destination.stringValue as NSString).expandingTildeInPath
            guard path.hasPrefix("/"), !path.contains("\0") else {
                alert.informativeText = "Choose a download folder using an absolute path, or use Choose…."
                continue
            }
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &directory),
               !directory.boolValue || !FileManager.default.isWritableFile(atPath: path) {
                alert.informativeText = "That location is not a writable folder. Choose another destination."
                continue
            }
            return TorrentAddOptions(destination: path, paused: start.state != .on, priority: priority.indexOfSelectedItem - 1)
        }
        return nil
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose download folder"; panel.prompt = "Choose"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        let path = (destination.stringValue as NSString).expandingTildeInPath
        if path.hasPrefix("/") { panel.directoryURL = URL(fileURLWithPath: path) }
        if panel.runModal() == .OK, let url = panel.url { destination.stringValue = url.path }
    }
}
