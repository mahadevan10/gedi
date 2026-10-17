import Testing
@testable import GediCore

private let matcher = WakeWordMatcher(wakeWords: GediConfig.default.wakeWords)

// Spellings below were produced by Apple's ml-IN recogniser from Piper saying ഗഡീ.
@Test func matchesRecognizerSpellings() {
    for heard in ["gadhi", "gadi", "gadiye", "Gadi.", "gedi", "gadeee", "geddi", "ഗഡീ", "ഗെഡി", "edi", "ede", "Yedi", "kedi", "Gandhi", "jedi", "Daddy", "ഗടി", "എടി"] {
        #expect(matcher.remainder(after: heard) == "", "should wake on \(heard)")
    }
}

@Test func returnsTextAfterWakeWord() {
    #expect(matcher.remainder(after: "gadi ennu enth pani cheyyanam") == "ennu enth pani cheyyanam")
    #expect(matcher.remainder(after: "gadiye nee yevida") == "nee yevida")
    #expect(matcher.remainder(after: "eda gadhi, vaa") == "vaa")
}

@Test func wakeWordGluedToNextWord() {
    let r = matcher.remainder(after: "yenthootta gadiyitra pinneyum shorts")
    #expect(r == "pinneyum shorts")
}

@Test func ignoresSimilarWords() {
    #expect(matcher.remainder(after: "gadu adakkanam") == nil)     // "installment", not gedi
    #expect(matcher.remainder(after: "ഗഡു അടയ്ക്കണം") == nil)
    #expect(matcher.remainder(after: "innu mazhayaanu") == nil)
    #expect(matcher.remainder(after: "") == nil)
}

@Test func normalizeCollapsesAndMaps() {
    #expect(WakeWordMatcher.normalize("ഗഡീീ") == "ഗഡി")
    #expect(WakeWordMatcher.normalize("GADEEE") == "gade")
    #expect(WakeWordMatcher.normalize("ഗ\u{200D}ഡി") == "ഗഡി")
}

@Test func customWakeWordsFromCalibration() {
    let m = WakeWordMatcher(wakeWords: ["kadi"])
    #expect(m.remainder(after: "kadi vaa") == "vaa")
    #expect(m.remainder(after: "gadi vaa") == nil)
}
