import CryptoKit
import Foundation
import SCSDKCameraKit
import SCSDKCameraKitLocalLensRuntime

public final class LocalLensBundle {
    public let groupID: String
    public let groupName: String
    public let lensCount: Int
    public var initializationExtension: AnyObject { runtimeExtension }

    let validatedAssetsByID: [String: ValidatedAsset]
    let validatedLenses: [ValidatedLens]
    var validatedAssetCount: Int { validatedAssetsByID.count }
    private let runtimeExtension: SCCameraKitLocalLensRuntimeExtension

    public init(manifestURL: URL, resourceRootURL: URL) throws {
        let manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        let manifest = try JSONDecoder().decode(LocalLensManifest.self, from: manifestData)
        guard manifest.schemaVersion == 1 else {
            throw LocalLensBundleError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        guard !manifest.group.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalLensBundleError.invalidGroupID(manifest.group.id)
        }

        let root = resourceRootURL.standardizedFileURL.resolvingSymlinksInPath()
        var assetsByID: [String: LocalLensManifest.Asset] = [:]
        var validatedAssets: [String: ValidatedAsset] = [:]

        for asset in manifest.assets {
            if let existing = assetsByID[asset.id] {
                guard existing == asset else {
                    throw LocalLensBundleError.conflictingAssetID(asset.id)
                }
                continue
            }
            guard asset.assetType == 7, asset.assetTiming == 6 else {
                throw LocalLensBundleError.invalidAssetMetadata(
                    id: asset.id,
                    assetType: asset.assetType,
                    assetTiming: asset.assetTiming
                )
            }

            let fileURL = try Self.resolveFile(asset.file, beneath: root)
            try Self.validatePackage(at: fileURL, relativePath: asset.file, expectedSHA256: asset.sha256)
            assetsByID[asset.id] = asset
            validatedAssets[asset.id] = ValidatedAsset(manifest: asset, fileURL: fileURL)
        }

        var seenLensIDs = Set<String>()
        var lenses: [ValidatedLens] = []
        for lens in manifest.lenses {
            guard seenLensIDs.insert(lens.id).inserted else {
                throw LocalLensBundleError.duplicateLensID(lens.id)
            }

            let packageURL = try Self.resolveFile(lens.file, beneath: root)
            try Self.validatePackage(at: packageURL, relativePath: lens.file, expectedSHA256: lens.sha256)
            let iconURL = try Self.resolveFile(lens.iconFile, beneath: root)
            try Self.requireRegularFile(iconURL, relativePath: lens.iconFile)

            let assets = try lens.assetIDs.map { assetID -> ValidatedAsset in
                guard let asset = validatedAssets[assetID] else {
                    throw LocalLensBundleError.missingAsset(assetID)
                }
                return asset
            }
            lenses.append(
                ValidatedLens(
                    manifest: lens,
                    packageURL: packageURL,
                    iconURL: iconURL,
                    assets: assets
                )
            )
        }

        groupID = manifest.group.id
        groupName = manifest.group.name
        lensCount = lenses.count
        validatedAssetsByID = validatedAssets
        validatedLenses = lenses

        let runtimeAssets = validatedAssets.mapValues { asset in
            SCCameraKitLocalLensRuntimeAssetDescriptor(
                identifier: asset.manifest.id,
                assetType: asset.manifest.assetType,
                assetTiming: asset.manifest.assetTiming,
                contentURL: asset.manifest.contentURL,
                checksum: asset.manifest.sha256.uppercased(),
                resourcePath: asset.fileURL.path
            )
        }
        let runtimeLenses = try lenses.map { lens -> SCCameraKitLocalLensRuntimeLensDescriptor in
            let assets = try lens.manifest.assetIDs.map { assetID -> SCCameraKitLocalLensRuntimeAssetDescriptor in
                guard let asset = runtimeAssets[assetID] else {
                    throw LocalLensBundleError.missingAsset(assetID)
                }
                return asset
            }
            return SCCameraKitLocalLensRuntimeLensDescriptor(
                identifier: lens.manifest.id,
                groupIdentifier: manifest.group.id,
                name: lens.manifest.name,
                iconURL: lens.iconURL,
                contentURL: lens.manifest.contentURL,
                checksum: lens.manifest.sha256.uppercased(),
                resourcePath: lens.packageURL.path,
                facingPreference: lens.manifest.facingPreference,
                assets: assets
            )
        }
        do {
            runtimeExtension = try SCCameraKitLocalLensRuntimeExtension(
                groupIdentifier: manifest.group.id,
                lenses: runtimeLenses
            )
        } catch {
            throw LocalLensBundleError.runtimeUnavailable(error.localizedDescription)
        }
    }

    public func register(
        with cameraKit: CameraKitProtocol,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        cameraKit.register(initializationExtension) { success, error in
            if success {
                completion(.success(()))
            } else {
                completion(
                    .failure(
                        error ?? LocalLensBundleError.runtimeUnavailable(
                            "Camera Kit rejected the local Lens extension"
                        )
                    )
                )
            }
        }
    }

    public func unregister() {
        runtimeExtension.unregisterLenses()
    }

    private static func resolveFile(_ relativePath: String, beneath root: URL) throws -> URL {
        let path = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !NSString(string: path).isAbsolutePath else {
            throw LocalLensBundleError.pathEscapesResourceRoot(relativePath)
        }

        let candidate = root
            .appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPath) else {
            throw LocalLensBundleError.pathEscapesResourceRoot(relativePath)
        }
        return candidate
    }

    private static func validatePackage(
        at fileURL: URL,
        relativePath: String,
        expectedSHA256: String
    ) throws {
        try requireRegularFile(fileURL, relativePath: relativePath)
        let normalizedHash = try normalizeSHA256(expectedSHA256)
        let actualHash = try sha256(of: fileURL)
        guard actualHash == normalizedHash else {
            throw LocalLensBundleError.hashMismatch(
                path: relativePath,
                expected: normalizedHash,
                actual: actualHash
            )
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { handle.closeFile() }
        let header = handle.readData(ofLength: 8)
        guard header.count == 8, Array(header.prefix(4)) == [0x4C, 0x5A, 0x43, 0x00] else {
            throw LocalLensBundleError.invalidLZCHeader(relativePath)
        }
        let version = header.dropFirst(4).prefix(4).enumerated().reduce(UInt32(0)) { value, byte in
            value | (UInt32(byte.element) << UInt32(byte.offset * 8))
        }
        guard version == 1 || version == 2 else {
            throw LocalLensBundleError.unsupportedLZCVersion(path: relativePath, version: version)
        }
    }

    private static func requireRegularFile(_ fileURL: URL, relativePath: String) throws {
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else {
            throw LocalLensBundleError.missingFile(relativePath)
        }
    }

    private static func normalizeSHA256(_ value: String) throws -> String {
        let normalized = value.uppercased()
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard normalized.count == 64,
              normalized.unicodeScalars.allSatisfy(allowed.contains)
        else {
            throw LocalLensBundleError.invalidSHA256(value)
        }
        return normalized
    }

    private static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { handle.closeFile() }

        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1_048_576)
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02X", $0) }.joined()
    }
}

struct ValidatedAsset {
    let manifest: LocalLensManifest.Asset
    let fileURL: URL
}

struct ValidatedLens {
    let manifest: LocalLensManifest.Lens
    let packageURL: URL
    let iconURL: URL
    let assets: [ValidatedAsset]
}
