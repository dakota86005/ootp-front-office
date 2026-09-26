import Testing
@testable import PennantDesign

@Suite("Club tint")
struct ClubTintTests {
    @Test("the contrast ratio is WCAG's: black on white is 21:1, a colour on itself 1:1")
    func contrastRatio() {
        #expect(abs(ClubTint.contrast((0, 0, 0), (1, 1, 1)) - 21) < 0.001)
        #expect(abs(ClubTint.contrast((0.5, 0.2, 0.1), (0.5, 0.2, 0.1)) - 1) < 0.001)
    }

    @Test("the club's own foreground is kept when it reads")
    func servedPairKept() {
        let tint = ClubTint(background: "#1d2d44", foreground: "#f0ebd8")
        #expect(tint.textChoice(increasedContrast: false) == .served)
        #expect(tint.textChoice(increasedContrast: true) == .served)
    }

    @Test("a foreground that does not read becomes black or white; Increase Contrast asks for 7:1")
    func unreadableReplaced() {
        #expect(ClubTint(background: "#777777", foreground: "#888888").textChoice(increasedContrast: false) != .served)
        #expect(ClubTint(background: "#ffffff", foreground: "#dddddd").textChoice(increasedContrast: false) == .black)
        #expect(ClubTint(background: "#000000", foreground: nil).textChoice(increasedContrast: false) == .white)
        let red = ClubTint(background: "#ffffff", foreground: "#dd1111")
        #expect(red.textChoice(increasedContrast: false) == .served)
        #expect(red.textChoice(increasedContrast: true) == .black)
    }

    @Test("a fill on which neither black nor white reads at the needed contrast is drawn neutral")
    func neitherReads() {
        // Mid grey: about 4.7:1 with black, 4.5 with white; neither reaches 7:1
        let grey = ClubTint(background: "#777777", foreground: "#888888")
        #expect(grey.textChoice(increasedContrast: false) == .black)
        #expect(grey.textChoice(increasedContrast: true) == .neutral)
        #expect(grey.fill(increasedContrast: true) == nil)
    }

    @Test("no served background: neutral, never white on the accent or an invented club colour")
    func noServedFill() {
        let tint = ClubTint(background: nil, foreground: "#ffffff")
        #expect(tint.textChoice(increasedContrast: false) == .neutral)
        #expect(tint.fill(increasedContrast: false) == nil)
        #expect(tint.text(increasedContrast: false) == nil)
        #expect(ClubTint(background: "navy", foreground: nil).textChoice(increasedContrast: false) == .neutral)
    }

    @Test("team colours turned off (the served useTeamColors) draw the card neutral")
    func teamColoursOff() {
        let tint = ClubTint(background: "#1d2d44", foreground: "#f0ebd8", useTeamColors: false)
        #expect(tint.textChoice(increasedContrast: false) == .neutral)
        #expect(tint.fill(increasedContrast: false) == nil)
    }
}
