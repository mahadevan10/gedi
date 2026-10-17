import Foundation

/// Finds "gedeee" in recognised text.
///
/// Apple's ml-IN recogniser writes Malayalam in Latin letters (Manglish), and it spells
/// the call several ways: "gadhi", "gadi", "gadiye", and sometimes glues it to the next
/// word ("gadiyitra" for "ഗഡീ ഇത്"). So a word matches when, after normalising, it
/// *starts with* one of the wake words. Normalising = lowercase, drop zero-width joiners,
/// long ീ → short ി, collapse repeated characters ("gadeee" → "gade", "geddi" → "gedi").
public struct WakeWordMatcher: Sendable {
    private let prefixes: [String]

    public init(wakeWords: [String]) {
        prefixes = wakeWords.map(Self.normalize).filter { !$0.isEmpty }
    }

    public static func normalize(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for scalar in s.lowercased().unicodeScalars {
            if scalar.value == 0x200C || scalar.value == 0x200D { continue }
            let mapped: Unicode.Scalar = scalar.value == 0x0D40 ? Unicode.Scalar(0x0D3F)! : scalar
            if mapped == previous { continue }
            out.append(mapped)
            previous = mapped
        }
        return String(out)
    }

    private static let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

    /// Nil if there is no wake word. Otherwise the text after the word that contained it,
    /// trimmed ("" when the user said only "gedeee").
    public func remainder(after text: String) -> String? {
        let tokens = text.split(whereSeparator: { c in
            c.unicodeScalars.allSatisfy { Self.separators.contains($0) }
        })
        for token in tokens {
            let word = Self.normalize(String(token))
            if prefixes.contains(where: { word.hasPrefix($0) }) {
                return String(text[token.endIndex...]).trimmingCharacters(in: Self.separators)
            }
        }
        return nil
    }
}
