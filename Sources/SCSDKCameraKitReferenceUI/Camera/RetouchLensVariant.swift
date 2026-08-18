//  Copyright Snap Inc. All rights reserved.

import Foundation

/// Host-provided Retouch implementations exposed by the native camera controls.
public enum RetouchLensVariant: String, CaseIterable, Sendable {
    case standard
    case machineLearning = "ml"

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .machineLearning: return "ML"
        }
    }
}

struct RetouchLensOptions<Value> {
    let standard: Value?
    let machineLearning: Value?

    subscript(variant: RetouchLensVariant) -> Value? {
        switch variant {
        case .standard: return standard
        case .machineLearning: return machineLearning
        }
    }

    var availableVariants: [RetouchLensVariant] {
        RetouchLensVariant.allCases.filter { self[$0] != nil }
    }

    var values: [Value] {
        availableVariants.compactMap { self[$0] }
    }

    func resolvedVariant(preferred: RetouchLensVariant) -> RetouchLensVariant? {
        if self[preferred] != nil {
            return preferred
        }
        return availableVariants.first
    }
}
