import Testing
@testable import HanyeongCore

/// Flattens effects into strings so sequences can be compared directly.
private func describe(_ effects: [SwitchCore<String>.Effect]) -> [String] {
    effects.map { effect in
        switch effect {
        case .performToggle(let generation): "toggle#\(generation)"
        case .post(let events): "post:" + events.joined(separator: ",")
        case .toggleCapsLock: "capsLock"
        case .armLongPress(let press): "arm#\(press)"
        }
    }
}

private func makeCore(shift: Bool = true, longPress: Bool = false) -> SwitchCore<String> {
    SwitchCore(options: .init(shiftTogglesCapsLock: shift, longPressTogglesCapsLock: longPress))
}

@Suite struct SwitchCoreTests {
    @Test func pressSwitchesImmediately() {
        var core = makeCore()
        #expect(describe(core.triggerDown(shift: false, isRepeat: false)) == ["toggle#1"])
        #expect(core.inFlight == 1)
    }

    @Test func keysPassThroughWhenIdle() {
        var core = makeCore()
        #expect(core.keyEvent("a", isKeyDown: true) == false)
    }

    @Test func keysTypedDuringSwitchAreHeldAndReplayedInOrder() {
        var core = makeCore()
        _ = core.triggerDown(shift: false, isRepeat: false)
        core.triggerUp()
        #expect(core.keyEvent("g↓", isKeyDown: true) == true)
        #expect(core.keyEvent("g↑", isKeyDown: false) == true)
        #expect(core.keyEvent("k↓", isKeyDown: true) == true)
        #expect(describe(core.switchCompleted(generation: 1)) == ["post:g↓,g↑,k↓"])
        #expect(core.inFlight == nil)
        #expect(core.keyEvent("s↓", isKeyDown: true) == false)
    }

    @Test func heldEventIsNotEvaluatedWhenIdle() {
        var core = makeCore()
        var evaluated = false
        func make() -> String { evaluated = true; return "a" }
        _ = core.keyEvent(make(), isKeyDown: true)
        #expect(evaluated == false)
    }

    @Test func secondPressDuringSwitchWaitsItsTurn() {
        var core = makeCore()
        _ = core.triggerDown(shift: false, isRepeat: false)
        _ = core.keyEvent("a", isKeyDown: true)
        #expect(describe(core.triggerDown(shift: false, isRepeat: false)) == [])
        _ = core.keyEvent("b", isKeyDown: true)

        // "a" was typed after the first press, "b" after the second.
        #expect(describe(core.switchCompleted(generation: 1)) == ["post:a", "toggle#2"])
        #expect(core.inFlight == 2)
        #expect(describe(core.switchCompleted(generation: 2)) == ["post:b"])
        #expect(core.inFlight == nil)
    }

    @Test func staleCompletionIsIgnored() {
        var core = makeCore()
        _ = core.triggerDown(shift: false, isRepeat: false)
        _ = core.keyEvent("a", isKeyDown: true)
        #expect(describe(core.switchCompleted(generation: 7)) == [])
        #expect(core.inFlight == 1)
    }

    @Test func autoRepeatOfTriggerIsIgnored() {
        var core = makeCore()
        _ = core.triggerDown(shift: false, isRepeat: false)
        #expect(describe(core.triggerDown(shift: false, isRepeat: true)) == [])
    }

    @Test func shiftPressTogglesCapsLockInsteadOfSwitching() {
        var core = makeCore(shift: true)
        #expect(describe(core.triggerDown(shift: true, isRepeat: false)) == ["capsLock"])
        #expect(core.inFlight == nil)
    }

    @Test func shiftPressSwitchesWhenOptionIsOff() {
        var core = makeCore(shift: false)
        #expect(describe(core.triggerDown(shift: true, isRepeat: false)) == ["toggle#1"])
    }

    @Test func longPressUndoesTheSwitchAndTogglesCapsLock() {
        var core = makeCore(longPress: true)
        #expect(describe(core.triggerDown(shift: false, isRepeat: false)) == ["toggle#1", "arm#1"])
        _ = core.switchCompleted(generation: 1)
        #expect(describe(core.longPressFired(press: 1)) == ["toggle#2", "capsLock"])
    }

    @Test func longPressWhileSwitchStillInFlightQueuesTheUndo() {
        var core = makeCore(longPress: true)
        _ = core.triggerDown(shift: false, isRepeat: false)
        #expect(describe(core.longPressFired(press: 1)) == ["capsLock"])
        #expect(describe(core.switchCompleted(generation: 1)) == ["toggle#2"])
    }

    @Test func releasingBeforeTheTimerCancelsLongPress() {
        var core = makeCore(longPress: true)
        _ = core.triggerDown(shift: false, isRepeat: false)
        core.triggerUp()
        #expect(describe(core.longPressFired(press: 1)) == [])
    }

    @Test func typingWhileHoldingCancelsLongPress() {
        var core = makeCore(longPress: true)
        _ = core.triggerDown(shift: false, isRepeat: false)
        _ = core.keyEvent("a", isKeyDown: true)
        #expect(describe(core.longPressFired(press: 1)) == [])
    }

    @Test func modifierChangeWhileHoldingDoesNotCancelLongPress() {
        var core = makeCore(longPress: true)
        _ = core.triggerDown(shift: false, isRepeat: false)
        _ = core.keyEvent("shift", isKeyDown: false)
        #expect(describe(core.longPressFired(press: 1)).contains("capsLock"))
    }

    @Test func timerFromAnEarlierPressIsIgnored() {
        var core = makeCore(longPress: true)
        _ = core.triggerDown(shift: false, isRepeat: false)
        core.triggerUp()
        _ = core.switchCompleted(generation: 1)
        _ = core.triggerDown(shift: false, isRepeat: false)
        #expect(describe(core.longPressFired(press: 1)) == [])
    }

    @Test func resetReleasesHeldEventsAndDropsQueuedPresses() {
        var core = makeCore()
        _ = core.triggerDown(shift: false, isRepeat: false)
        _ = core.keyEvent("a", isKeyDown: true)
        _ = core.triggerDown(shift: false, isRepeat: false)
        _ = core.keyEvent("b", isKeyDown: true)
        #expect(core.reset() == ["a", "b"])
        #expect(core.inFlight == nil)
        #expect(core.keyEvent("c", isKeyDown: true) == false)
    }
}
