import Foundation

public enum SpriteFrame: CaseIterable, Sendable {
    case idle, walk1, walk2, talk
}

/// Placeholder pixel art: a Thrissur guy with a moustache, blue shirt and kasavu mundu.
/// 16×24 pixels; each character is one pixel, `.` is transparent. Swap in real art later.
public enum SpriteArt {
    public static let width = 16
    public static let height = 24

    /// RGB hex per pixel character.
    public static let palette: [Character: UInt32] = [
        "H": 0x1B1B1B, // hair
        "S": 0x8D5524, // skin
        "E": 0x000000, // eyes
        "M": 0x1B1B1B, // moustache
        "O": 0x7A1F1F, // open mouth
        "C": 0x4A90D9, // shirt
        "W": 0xF5F5F0, // mundu
        "G": 0xD4AF37, // kasavu (gold) border
        "B": 0x5B3A1E, // sandals
    ]

    private static let head = [
        ".....HHHHHH.....",
        "....HHHHHHHH....",
        "....HSSSSSSH....",
        "....SSSSSSSS....",
        "....SESSSSES....",
        "....SSSSSSSS....",
        "....SMMMMMMS....",
    ]
    private static let mouthClosed = "....SSSSSSSS...."
    private static let mouthOpen = "....SSSOOSSS...."
    private static let body = [
        ".....SSSSSS.....",
        "......SSSS......",
        "...CCCCCCCCCC...",
        "..CCCCCCCCCCCC..",
        "..CCCCCCCCCCCC..",
        "..SCCCCCCCCCCS..",
        "..SCCCCCCCCCCS..",
        "...WWWWWWWWWW...",
        "...WWWWWWWWWW...",
        "...WWWWWWWWWW...",
        "...WWWWWWWWWW...",
        "...WWWWWWWWWW...",
        "...GGGGGGGGGG...",
    ]
    private static let feetStand = [
        "....SS....SS....",
        "....BB....BB....",
        "...BBB....BBB...",
    ]
    private static let feetWide = [
        "...SS......SS...",
        "...BB......BB...",
        "..BBB......BBB..",
    ]
    private static let feetNarrow = [
        ".....SS..SS.....",
        ".....BB..BB.....",
        "....BBB..BBB....",
    ]

    public static func rows(_ frame: SpriteFrame) -> [String] {
        switch frame {
        case .idle: return head + [mouthClosed] + body + feetStand
        case .walk1: return head + [mouthClosed] + body + feetWide
        case .walk2: return head + [mouthClosed] + body + feetNarrow
        case .talk: return head + [mouthOpen] + body + feetStand
        }
    }
}
