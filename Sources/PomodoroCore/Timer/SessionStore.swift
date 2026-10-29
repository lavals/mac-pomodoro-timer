import Foundation

/// Persists the current `TimerState` as JSON under one key in an injected `UserDefaults`,
/// so a running session survives quitting and relaunching the app.
public final class SessionStore {
    /// UserDefaults keys. Saved sessions are read back under these names, so never change them.
    enum Key {
        static let state = "sessionState"
        static let focusTurnedOn = "focusTurnedOn"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Stores `state`, replacing whatever was saved before.
    public func save(_ state: TimerState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Key.state)
    }

    /// The saved state, or nil when nothing was saved or the data cannot be decoded.
    public func load() -> TimerState? {
        guard let data = defaults.data(forKey: Key.state) else { return nil }
        return try? JSONDecoder().decode(TimerState.self, from: data)
    }

    /// Whether the app ran the Focus On shortcut and has not turned Focus off since. Saved next
    /// to the state so a relaunch knows whether Focus Off is the app's to run.
    public var focusTurnedOn: Bool {
        get { defaults.bool(forKey: Key.focusTurnedOn) }
        set { defaults.set(newValue, forKey: Key.focusTurnedOn) }
    }
}
