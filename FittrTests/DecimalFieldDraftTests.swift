import Testing
@testable import Fittr

struct DecimalFieldDraftTests {
    @Test func aWholeNumberIsNotShownWithATrailingZero() {
        #expect(DecimalFieldDraft.display(5) == "5")
        #expect(DecimalFieldDraft.display(Optional(5.0)) == "5")
    }

    @Test func decimalsStayAsTypedOnceStored() {
        #expect(DecimalFieldDraft.commit("5.4") == .value(5.4))
        #expect(DecimalFieldDraft.display(5.4) == "5.4")
        #expect(DecimalFieldDraft.commit("2.25") == .value(2.25))
        #expect(DecimalFieldDraft.display(2.25) == "2.25")
    }

    /// Leaving the field on "5." is a finished 5, not a reason to snap back.
    @Test func aTrailingSeparatorStillStoresTheNumber() {
        #expect(DecimalFieldDraft.commit("5.") == .value(5))
        #expect(DecimalFieldDraft.commit("5,4") == .value(5.4))
    }

    @Test func anEmptyFieldClearsAndGarbageIsRejected() {
        #expect(DecimalFieldDraft.commit("") == .empty)
        #expect(DecimalFieldDraft.commit("  ") == .empty)
        #expect(DecimalFieldDraft.commit("5.4.2") == .invalid)
        #expect(DecimalFieldDraft.display(Optional<Double>.none) == "")
    }
}
