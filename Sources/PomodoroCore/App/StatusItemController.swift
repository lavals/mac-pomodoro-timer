import AppKit
import Observation

/// The menu bar item: a glyph plus an optional countdown, a popover on left click and a menu
/// on right click (or control-click).
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let coordinator: TimerCoordinator
    private let statusItem: NSStatusItem
    /// Menu entries behind each item's tag, rebuilt every time the menu opens.
    private var shownItems: [MenuItem] = []

    public init(coordinator: TimerCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Pomodoro"
        }
        track()
    }

    // MARK: rendering

    /// Renders while recording which coordinator properties were read, and re-registers on the
    /// next change. `onChange` fires once, before the change lands, so hop to main and re-read.
    private func track() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.track() }
            }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let state = coordinator.state
        let showCountdown = coordinator.preferences.showCountdown
        button.image = StatusGlyph.image(spec: GlyphSpec.make(state: state, progress: coordinator.progress))
        button.attributedTitle = StatusTitle.make(
            time: coordinator.displayTime,
            phase: StatusTitle.phase(for: state),
            showCountdown: showCountdown
        )
        button.imagePosition = showCountdown ? .imageLeading : .imageOnly
    }

    // MARK: clicks

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let wantsMenu = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        if wantsMenu {
            showMenu()
        } else {
            togglePopover()
        }
    }

    /// Placeholder until the popover exists: left click shows the same menu so the timer is usable.
    private func togglePopover() {
        showMenu()
    }

    /// Assigns the menu only while it is open: a permanently assigned menu would swallow left clicks.
    private func showMenu() {
        shownItems = TimerPresentation.menuItems(for: coordinator.state)
        let menu = Self.makeMenu(
            items: shownItems,
            showCountdown: coordinator.preferences.showCountdown,
            target: self,
            action: #selector(menuItemChosen(_:))
        )
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    public func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    @objc private func menuItemChosen(_ sender: NSMenuItem) {
        guard shownItems.indices.contains(sender.tag) else { return }
        switch shownItems[sender.tag] {
        case .primary: coordinator.performPrimaryAction()
        case .skip: coordinator.skip()
        case .reset: coordinator.reset()
        case .toggleCountdown: coordinator.toggleCountdown()
        case .quit: NSApp.terminate(nil)
        case .settings, .separator: break
        }
    }

    /// Builds the right-click menu. Each item's tag is its index in `items`.
    /// "Settings…" stays disabled until the settings window exists.
    static func makeMenu(items: [MenuItem], showCountdown: Bool, target: AnyObject?, action: Selector?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, item) in items.enumerated() {
            if item == .separator {
                menu.addItem(.separator())
                continue
            }
            let menuItem = NSMenuItem(title: item.title, action: action, keyEquivalent: item == .quit ? "q" : "")
            menuItem.target = target
            menuItem.tag = index
            switch item {
            case .toggleCountdown: menuItem.state = showCountdown ? .on : .off
            case .settings: menuItem.isEnabled = false
            default: break
            }
            menu.addItem(menuItem)
        }
        return menu
    }
}
