import Foundation

public struct LocalLensManifest: Decodable, Equatable {
    public let schemaVersion: Int
    public let group: Group
    public let assets: [Asset]
    public let lenses: [Lens]

    public struct Group: Decodable, Equatable {
        public let id: String
        public let name: String
    }

    public struct Asset: Decodable, Equatable {
        public let id: String
        public let runtimeID: String?
        public let file: String
        public let sha256: String
        public let contentURL: URL
        public let assetType: Int
        public let assetTiming: Int
    }

    public struct Lens: Decodable, Equatable {
        public let id: String
        public let name: String
        public let file: String
        public let sha256: String
        public let contentURL: URL
        public let iconFile: String
        public let facingPreference: Int
        public let assetIDs: [String]
    }
}

public enum LocalLensBundleError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidGroupID(String)
    case duplicateLensID(String)
    case conflictingAssetID(String)
    case missingAsset(String)
    case pathEscapesResourceRoot(String)
    case missingFile(String)
    case invalidSHA256(String)
    case hashMismatch(path: String, expected: String, actual: String)
    case invalidLZCHeader(String)
    case unsupportedLZCVersion(path: String, version: UInt32)
    case invalidAssetMetadata(id: String, assetType: Int, assetTiming: Int)
    case runtimeUnavailable(String)
}

extension LocalLensBundleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            return "Unsupported local Lens manifest version \(version)"
        case let .invalidGroupID(groupID):
            return "Invalid local Lens group ID: \(groupID)"
        case let .duplicateLensID(lensID):
            return "Duplicate local Lens ID: \(lensID)"
        case let .conflictingAssetID(assetID):
            return "Conflicting local Lens asset ID: \(assetID)"
        case let .missingAsset(assetID):
            return "Missing local Lens asset: \(assetID)"
        case let .pathEscapesResourceRoot(path):
            return "Local Lens path escapes fixture root: \(path)"
        case let .missingFile(path):
            return "Missing local Lens file: \(path)"
        case let .invalidSHA256(value):
            return "Invalid local Lens SHA-256: \(value)"
        case let .hashMismatch(path, expected, actual):
            return "Local Lens hash mismatch for \(path): expected \(expected), received \(actual)"
        case let .invalidLZCHeader(path):
            return "Invalid LZC header: \(path)"
        case let .unsupportedLZCVersion(path, version):
            return "Unsupported LZC version \(version): \(path)"
        case let .invalidAssetMetadata(id, assetType, assetTiming):
            return "Unexpected metadata for local Lens asset \(id): type \(assetType), timing \(assetTiming)"
        case let .runtimeUnavailable(reason):
            return "Local Lens runtime unavailable: \(reason)"
        }
    }
}
