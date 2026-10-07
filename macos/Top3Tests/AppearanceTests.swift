import XCTest

final class AppearanceTests: XCTestCase {
    // MARK: Contrast math

    func testRatioEndpoints() {
        XCTAssertEqual(Contrast.ratio(0x000000, 0xFFFFFF), 21, accuracy: 0.001)
        XCTAssertEqual(Contrast.ratio(0xFFFFFF, 0x000000), 21, accuracy: 0.001)
        XCTAssertEqual(Contrast.ratio(0x5B6283, 0x5B6283), 1, accuracy: 0.001)
    }

    func testRatioKnownPairs() {
        // #777777 on white is the classic just-under-AA grey; #767676 is the lightest that passes.
        XCTAssertLessThan(Contrast.ratio(0x777777, 0xFFFFFF), Contrast.text)
        XCTAssertGreaterThanOrEqual(Contrast.ratio(0x767676, 0xFFFFFF), Contrast.text)
    }

    func testOverBlendsChannels() {
        XCTAssertEqual(Contrast.over(0x000000, alpha: 0.5, 0xFFFFFF), 0x808080)
        XCTAssertEqual(Contrast.over(0xFF0000, alpha: 1, 0x00FF00), 0xFF0000)
        XCTAssertEqual(Contrast.over(0xFF0000, alpha: 0, 0x00FF00), 0x00FF00)
    }

    // MARK: Every combination

    /// The same check the build runs; failing here names every pair below its minimum.
    func testEveryStyleModeAndAccentIsReadable() {
        XCTAssertEqual(Contrast.violations(), [])
    }

    func testCheckCoversEveryCombination() {
        let combos = Contrast.allSelections()
        // Five two-mode styles and Midnight; Mono has no accents to vary.
        let expected = 2 * 8 * 4 + 1 * 8 + 2 * 1
        XCTAssertEqual(combos.count, expected)
        XCTAssertTrue(combos.contains { $0.0.style == .midnight && $0.1 == .dark })
        XCTAssertFalse(combos.contains { $0.0.style == .midnight && $0.1 == .light })
    }

    func testCheckFlagsALowContrastPair() {
        let pair = Contrast.Pair(name: "test", foreground: 0xA1A1AA, background: 0xFFFFFF, minimum: Contrast.text)
        XCTAssertFalse(pair.passes)
    }

    // MARK: Rules

    func testModesPerStyle() {
        XCTAssertEqual(AppearanceRules.modes(for: .graphite), [.system, .light, .dark])
        XCTAssertEqual(AppearanceRules.modes(for: .midnight), [.dark])
        for style in AppearanceStyle.allCases {
            XCTAssertFalse(AppearanceRules.modes(for: style).isEmpty, style.title)
        }
    }

    func testEffectiveModeFallsBackForSingleModeStyles() {
        XCTAssertEqual(AppearanceRules.effectiveMode(AppearanceSelection(mode: .light, style: .midnight)), .dark)
        XCTAssertEqual(AppearanceRules.effectiveMode(AppearanceSelection(mode: .system, style: .midnight)), .dark)
        XCTAssertEqual(AppearanceRules.effectiveMode(AppearanceSelection(mode: .light, style: .paper)), .light)
        XCTAssertEqual(AppearanceRules.effectiveMode(AppearanceSelection(mode: .system, style: .graphite)), .system)
    }

    func testSingleVariantStyleUsesItsOnlyTokensForBoth() {
        XCTAssertEqual(AppearanceRules.tokens(.midnight, .light), AppearanceRules.tokens(.midnight, .dark))
    }

    func testAccentFollowsStyleUnlessChosen() {
        XCTAssertEqual(AppearanceRules.accent(AppearanceSelection(style: .graphite)), .iris)
        XCTAssertEqual(AppearanceRules.accent(AppearanceSelection(style: .midnight)), .blue)
        XCTAssertEqual(AppearanceRules.accent(AppearanceSelection(style: .sand, accent: .plum)), .plum)
    }

    func testMonoHasNoAccentAndUsesItsTextColor() {
        let s = AppearanceSelection(style: .mono, accent: .rose)
        XCTAssertNil(AppearanceRules.accent(s))
        XCTAssertEqual(AppearanceRules.accentColor(s, .light), AppearanceRules.tokens(.mono, .light).text)
        XCTAssertEqual(AppearanceRules.accentForeground(s, .dark), AppearanceRules.tokens(.mono, .dark).background)
    }

    func testFontOnlyHonoredWhenTheStyleOffersIt() {
        XCTAssertEqual(AppearanceRules.font(AppearanceSelection(style: .paper)), .serif)
        XCTAssertEqual(AppearanceRules.font(AppearanceSelection(style: .paper, font: .humanist)), .humanist)
        XCTAssertEqual(AppearanceRules.font(AppearanceSelection(style: .graphite, font: .humanist)), .inter)
    }

    func testAccentChoicesAndShapesStayWithinTheDesignSystem() {
        XCTAssertTrue((6...8).contains(AccentChoice.allCases.count))
        for style in AppearanceStyle.allCases {
            XCTAssertLessThanOrEqual(style.spec.radiusMedium, 6, style.title)
            XCTAssertLessThanOrEqual(style.spec.radiusSmall, style.spec.radiusMedium, style.title)
            XCTAssertGreaterThan(style.spec.hairline, 0, style.title)
        }
    }

    // MARK: Saved selection

    func testSelectionRoundTrips() throws {
        let s = AppearanceSelection(mode: .dark, style: .sand, accent: .teal, font: nil)
        let back = try JSONDecoder().decode(AppearanceSelection.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testUnknownValuesFallBackInsteadOfFailing() throws {
        let json = Data(#"{"mode":"dusk","style":"neon","accent":"teal","font":"comic"}"#.utf8)
        let s = try JSONDecoder().decode(AppearanceSelection.self, from: json)
        XCTAssertEqual(s, AppearanceSelection(mode: .system, style: .graphite, accent: .teal, font: nil))
    }
}
