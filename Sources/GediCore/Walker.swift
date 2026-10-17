import Foundation

/// Gedi's movement along the bottom of the screen. Pure state, advanced by `step`.
/// Walks at `speed` points/s, turns at the edges, pauses now and then, and stops
/// to face the user while talking.
public struct Walker: Sendable {
    public enum Mode: Equatable, Sendable {
        case walking
        case resting(until: TimeInterval)
        case talking
    }

    /// Settable so the user can drag Gedi around.
    public var x: Double
    public private(set) var facingRight: Bool
    public private(set) var mode: Mode = .walking
    /// Put down somewhere by the user: stays at `x` (still talks) until unpinned.
    public var pinned = false
    public var speed: Double = 40
    /// Chance per second of stopping for a rest while walking.
    public var restChancePerSecond: Double = 0.08
    private var clock: TimeInterval = 0

    public init(x: Double, facingRight: Bool = true) {
        self.x = x
        self.facingRight = facingRight
    }

    public mutating func step<R: RandomNumberGenerator>(dt: Double, minX: Double, maxX: Double, random: inout R) {
        clock += dt
        if pinned { return }
        switch mode {
        case .talking:
            return
        case .resting(let until):
            if clock >= until {
                mode = .walking
                if Double.random(in: 0..<1, using: &random) < 0.5 { facingRight.toggle() }
            }
        case .walking:
            x += (facingRight ? speed : -speed) * dt
            if x >= maxX {
                x = maxX
                facingRight = false
            } else if x <= minX {
                x = minX
                facingRight = true
            } else if Double.random(in: 0..<1, using: &random) < restChancePerSecond * dt {
                mode = .resting(until: clock + Double.random(in: 2...6, using: &random))
            }
        }
    }

    public mutating func setTalking(_ talking: Bool) {
        if talking {
            mode = .talking
        } else if mode == .talking {
            mode = .resting(until: clock + 1.5)
        }
    }

    /// Which sprite to draw now: legs alternate while walking, mouth flaps while talking.
    public var frame: SpriteFrame {
        switch mode {
        case .walking: return Int(clock * 6) % 2 == 0 ? .walk1 : .walk2
        case .resting: return .idle
        case .talking: return Int(clock * 5) % 2 == 0 ? .talk : .idle
        }
    }
}
