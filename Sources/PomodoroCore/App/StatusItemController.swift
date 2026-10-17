import AppKit
import Observation
import SwiftUI

/// The menu bar item: a glyph plus an optional countdown, a popover on left click and a menu
/// on right click (or control-click).
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let coordinator: TimerCoordinator
    private let statusItem: NSStatusItem
    private let openSettings: () -> Void
    private let openFocusSetup: () -> Void
    private var renderer: StatusButtonRenderer?
    /// Menu entries behind each item's tag, rebuilt every time the menu opens.
    private var shownItems: [MenuItem] = []

    private lazy var popover: NSPopover = Self.makePopover(
        coordinator: coordinator,
        openSettings: { [weak self] in
            self?.popover.performClose(nil)
            self?.openSettings()
        },
        openFocusSetup: { [weak self] in
            self?.popover.performClose(nil)
            self?.openFocusSetup()
        }
    )

    /// - Parameters:
    ///   - openSettings: shows the settings window (menu item and popover gear button).
    ///   - openFocusSetup: shows the Focus setup window (the popover's Focus hint).
    public init(
        coordinator: TimerCoordinator,
        openSettings: @escaping () -> Void,
        openFocusSetup: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.openSettings = openSettings
        self.openFocusSetup = openFocusSetup
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Pomodoro"
            let renderer = StatusButtonRenderer(button: button, coordinator: coordinator)
            renderer.start()
            self.renderer = renderer
        }
    }

    // MARK: clicks

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if Self.wantsMenu(eventType: event.type, modifierFlags: event.modifierFlags) {
            showMenu()
        } else {
            togglePopover()
        }
    }

    /// Right click or control-click opens the menu; a plain left click toggles the popover.
    static func wantsMenu(eventType: NSEvent.EventType, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        eventType == .rightMouseUp || (eventType == .leftMouseUp && modifierFlags.contains(.control))
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        // an accessory app must be active for the transient popover to close on outside clicks
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // checked after showing so the shortcuts call never delays the popover
        coordinator.refreshFocusAvailability()
    }

    /// Assigns the menu only while it is open: a permanently assigned menu would swallow left clicks.
    private func showMenu() {
        if popover.isShown { popover.performClose(nil) }
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
        case .settings: openSettings()
        case .quit: NSApp.terminate(nil)
        case let item: coordinator.perform(item)
        }
    }

    /// A transient popover hosting `PopoverView`, sized by the view's own preferred size.
    static func makePopover(
        coordinator: TimerCoordinator,
        openSettings: @escaping () -> Void,
        openFocusSetup: @escaping () -> Void
    ) -> NSPopover {
        let hosting = NSHostingController(rootView: PopoverView(
            coordinator: coordinator,
            openSettings: openSettings,
            openFocusSetup: openFocusSetup
        ))
        hosting.sizingOptions = .preferredContentSize
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hosting
        return popover
    }

    /// Builds the right-click menu. Each item's tag is its index in `items`.
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
            default: break
            }
            menu.addItem(menuItem)
        }
        return menu
    }
}

/// Keeps the status item's button in sync with the coordinator: glyph, countdown title and
/// image position. Works on any `NSButton`, so tests need no real status item.
@MainActor
final class StatusButtonRenderer {
    private let button: NSButton
    private let coordinator: TimerCoordinator

    init(button: NSButton, coordinator: TimerCoordinator) {
        self.button = button
        self.coordinator = coordinator
    }

    /// Renders now and again after every change of what the last render read.
    func start() {
        track()
    }

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
        let state = coordinator.state
        let showCountdown = coordinator.preferences.showCountdown
        button.image = StatusGlyph.image(spec: GlyphSpec.make(state: state, progress: coordinator.progress))
        button.attributedTitle = StatusTitle.make(
            time: coordinator.displayTime,
            tint: TimerPresentation.tint(for: state),
            showCountdown: showCountdown
        )
        button.imagePosition = showCountdown ? .imageLeading : .imageOnly
    }
}
