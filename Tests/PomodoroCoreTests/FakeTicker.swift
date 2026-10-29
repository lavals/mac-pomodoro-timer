import Foundation
@testable import PomodoroCore

/// Ticker driven by hand: `fire()` stands in for one second passing.
@MainActor
final class FakeTicker: Ticker {
    private let onFire: @MainActor () -> Void
    private(set) var isInvalidated = false

    init(fire: @escaping @MainActor () -> Void) {
        onFire = fire
    }

    func fire() {
        onFire()
    }

    func invalidate() {
        isInvalidated = true
    }
}

/// Hands out `FakeTicker`s and remembers them.
@MainActor
final class FakeTickerFactory {
    private(set) var tickers: [FakeTicker] = []

    /// The ticker that is currently running, if any.
    var active: FakeTicker? {
        tickers.last.flatMap { $0.isInvalidated ? nil : $0 }
    }

    var make: TickerFactory {
        { [unowned self] fire in
            let ticker = FakeTicker(fire: fire)
            tickers.append(ticker)
            return ticker
        }
    }
}
