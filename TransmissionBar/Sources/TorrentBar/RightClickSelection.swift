import AppKit
import SwiftUI

/// Explicitly open an AppKit menu instead of relying on SwiftUI's context-menu
/// recognizer inside a nonactivating floating panel.
struct RightClickSelection: NSViewRepresentable {
    let select: () -> Void
    let menu: () -> NSMenu
    func makeNSView(context: Context) -> SelectionObserver { SelectionObserver(select: select, menu: menu) }
    func updateNSView(_ view: SelectionObserver, context: Context) { view.select = select; view.makeMenu = menu }
    final class SelectionObserver: NSView {
        var select: () -> Void
        var makeMenu: () -> NSMenu
        private var monitor: Any?
        init(select: @escaping () -> Void, menu: @escaping () -> NSMenu) {
            self.select = select; self.makeMenu = menu; super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, !self.isHiddenOrHasHiddenAncestor, event.window === self.window,
                      event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                      self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.select()
                NSMenu.popUpContextMenu(self.makeMenu(), with: event, for: self)
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

@MainActor
enum NativeTransferMenu {
    private final class Action: NSObject {
        let callback: () -> Void
        init(_ callback: @escaping () -> Void) { self.callback = callback }
        @objc func invoke(_ sender: Any?) { callback() }
    }
    static func make(store: TorrentStore) -> NSMenu {
        let menu = NSMenu(title: "Transfers")
        menu.autoenablesItems = false
        let selected = !store.selectedIDs.isEmpty && store.canAct
        func add(_ title: String, enabled: Bool, to parent: NSMenu? = nil, action: @escaping () -> Void) {
            let target = Action(action)
            let item = NSMenuItem(title: title, action: #selector(Action.invoke(_:)), keyEquivalent: "")
            item.target = target; item.representedObject = target; item.isEnabled = enabled
            (parent ?? menu).addItem(item)
        }
        add("Pause Selected", enabled: selected) { store.act(.stop) }
        add("Resume Selected", enabled: selected) { store.act(.start) }
        add("Resume Selected Right Away", enabled: selected) { store.act(.startNow) }
        menu.addItem(.separator())
        add("Pause All", enabled: store.canAct && !store.torrents.isEmpty) { store.act(.stop, all: true) }
        add("Resume All", enabled: store.canAct && !store.torrents.isEmpty) { store.act(.start, all: true) }
        add("Resume All Waiting", enabled: store.canAct) { store.commandHandler?("resumeWaiting") }
        menu.addItem(.separator())
        add("Remove From List…", enabled: selected) { store.commandHandler?("remove") }
        add("Remove and Trash Data…", enabled: selected) { store.commandHandler?("trash") }
        add("Remove All Completed From List…", enabled: store.canAct) { store.commandHandler?("removeCompleted") }
        menu.addItem(.separator())
        add("Update Tracker", enabled: selected) { store.act(.reannounce) }
        add("Verify Local Data", enabled: selected) { store.act(.verify) }
        let queue = NSMenu(title: "Queue Position"); queue.autoenablesItems = false
        add("Move to Top", enabled: selected, to: queue) { store.act(.top) }
        add("Move Up", enabled: selected, to: queue) { store.act(.up) }
        add("Move Down", enabled: selected, to: queue) { store.act(.down) }
        add("Move to Bottom", enabled: selected, to: queue) { store.act(.bottom) }
        let item = NSMenuItem(title: "Queue Position", action: nil, keyEquivalent: "")
        item.submenu = queue; item.isEnabled = selected; menu.addItem(item)
        return menu
    }
}
