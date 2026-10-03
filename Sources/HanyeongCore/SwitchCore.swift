import Foundation

/// The 한영 switching state machine, independent of how events arrive or are posted.
///
/// Switching the input source is asynchronous: for some tens of milliseconds after the
/// switch is requested, keys still land in the previous language. So from the moment a
/// switch starts until it is confirmed, every key event is held here and replayed in
/// order afterwards.
public struct SwitchCore<Event> {
    public struct Options: Equatable, Sendable {
        public var shiftTogglesCapsLock: Bool
        public var longPressTogglesCapsLock: Bool

        public init(shiftTogglesCapsLock: Bool = true, longPressTogglesCapsLock: Bool = true) {
            self.shiftTogglesCapsLock = shiftTogglesCapsLock
            self.longPressTogglesCapsLock = longPressTogglesCapsLock
        }
    }

    public enum Effect {
        /// Ask the system to switch now, then report back with `switchCompleted(generation:)`.
        case performToggle(generation: Int)
        /// Replay these held events, in order.
        case post([Event])
        case toggleCapsLock
        /// Call `longPressFired(press:)` once the long-press duration has passed.
        case armLongPress(press: Int)
    }

    private enum Item {
        case event(Event)
        case toggle
    }

    public var options: Options
    /// The generation of the switch that is currently in progress, if any.
    public private(set) var inFlight: Int?

    private var generation = 0
    private var buffer: [Item] = []
    private var press = 0
    /// The press that can still turn into a long press.
    private var heldPress: Int?

    public init(options: Options = Options()) {
        self.options = options
    }

    public mutating func triggerDown(shift: Bool, isRepeat: Bool) -> [Effect] {
        if isRepeat { return [] }
        press += 1
        if shift && options.shiftTogglesCapsLock {
            heldPress = nil
            return [.toggleCapsLock]
        }
        var effects = requestToggle()
        if options.longPressTogglesCapsLock {
            heldPress = press
            effects.append(.armLongPress(press: press))
        } else {
            heldPress = nil
        }
        return effects
    }

    public mutating func triggerUp() {
        heldPress = nil
    }

    /// Returns `true` if the event was held and must not reach the application yet.
    /// The event is only evaluated when it is actually held.
    public mutating func keyEvent(_ event: @autoclosure () -> Event, isKeyDown: Bool) -> Bool {
        // Typing while the 한영 key is still down is rollover, not a long press.
        if isKeyDown { heldPress = nil }
        guard inFlight != nil else { return false }
        buffer.append(.event(event()))
        return true
    }

    public mutating func switchCompleted(generation completed: Int) -> [Effect] {
        guard inFlight == completed else { return [] }
        inFlight = nil
        var ready: [Event] = []
        while !buffer.isEmpty {
            switch buffer.removeFirst() {
            case .event(let event):
                ready.append(event)
            case .toggle:
                // Events typed before this second press belong to the language just
                // switched to; the rest stay held for the next switch.
                return (ready.isEmpty ? [] : [.post(ready)]) + begin()
            }
        }
        return ready.isEmpty ? [] : [.post(ready)]
    }

    /// The 한영 key was held long enough: undo the switch it made and toggle Caps Lock instead.
    public mutating func longPressFired(press fired: Int) -> [Effect] {
        guard heldPress == fired else { return [] }
        heldPress = nil
        return requestToggle() + [.toggleCapsLock]
    }

    /// Abandons any switch in progress and returns the held events so they can be released.
    public mutating func reset() -> [Event] {
        inFlight = nil
        heldPress = nil
        let events = buffer.compactMap { item -> Event? in
            if case .event(let event) = item { return event }
            return nil
        }
        buffer.removeAll()
        return events
    }

    private mutating func requestToggle() -> [Effect] {
        if inFlight != nil {
            buffer.append(.toggle)
            return []
        }
        return begin()
    }

    private mutating func begin() -> [Effect] {
        generation += 1
        inFlight = generation
        return [.performToggle(generation: generation)]
    }
}
