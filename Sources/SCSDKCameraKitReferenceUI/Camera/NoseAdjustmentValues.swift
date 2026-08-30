//  Copyright Snap Inc. All rights reserved.

import Foundation

/// Values consumed by the Vibe Check Nose Adjustments Lens.
public struct NoseAdjustmentValues: Equatable, Sendable {
    public static let original = NoseAdjustmentValues(width: 0, height: 0, gap: 0)

    public let width: Double
    public let height: Double
    public let gap: Double

    public init(width: Double, height: Double, gap: Double) {
        self.width = Self.clamp(width)
        self.height = Self.clamp(height)
        self.gap = Self.clamp(gap)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }
}

/// Presets authored by the Nose Adjustments Lens project.
public enum NoseAdjustmentPreset: Int, CaseIterable, Sendable {
    case original
    case petite
    case refined
    case lifted
    case sculpted
    case soft
    case bold

    public var displayName: String {
        switch self {
        case .original: return "Original"
        case .petite: return "Petite"
        case .refined: return "Refined"
        case .lifted: return "Lifted"
        case .sculpted: return "Sculpted"
        case .soft: return "Soft"
        case .bold: return "Bold"
        }
    }

    public var values: NoseAdjustmentValues {
        switch self {
        case .original: return .original
        case .petite: return NoseAdjustmentValues(width: -0.45, height: -0.25, gap: -0.15)
        case .refined: return NoseAdjustmentValues(width: -0.28, height: 0.18, gap: -0.20)
        case .lifted: return NoseAdjustmentValues(width: -0.18, height: 0.34, gap: 0.18)
        case .sculpted: return NoseAdjustmentValues(width: -0.38, height: 0.42, gap: 0.05)
        case .soft: return NoseAdjustmentValues(width: 0.18, height: -0.16, gap: -0.12)
        case .bold: return NoseAdjustmentValues(width: 0.35, height: 0.20, gap: 0.16)
        }
    }

    public static func matching(_ values: NoseAdjustmentValues, tolerance: Double = 0.001) -> Self? {
        allCases.first { preset in
            abs(preset.values.width - values.width) <= tolerance
                && abs(preset.values.height - values.height) <= tolerance
                && abs(preset.values.gap - values.gap) <= tolerance
        }
    }
}
