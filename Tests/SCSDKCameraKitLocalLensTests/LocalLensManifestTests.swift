import CryptoKit
import Foundation
import UIKit
import XCTest
@testable import SCSDKCameraKitLocalLens
import SCSDKCameraKitLocalLensRuntime
import SCSDKCameraKitReferenceUI

private final class RejectingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

final class LocalLensManifestTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var resourceRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        resourceRoot = temporaryDirectory.appendingPathComponent("fixture", isDirectory: true)
        try FileManager.default.createDirectory(
            at: resourceRoot,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testDecodesVersionOneManifest() throws {
        let manifestURL = try makeValidFixture()

        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(LocalLensManifest.self, from: data)

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.group.id, "test.local")
        XCTAssertEqual(manifest.lenses.map(\.id), ["lens-one", "lens-two"])
        XCTAssertEqual(manifest.assets.map(\.id), ["asset-shared"])
    }

    func testRejectsUnknownSchemaVersion() throws {
        let manifestURL = try makeValidFixture { manifest in
            manifest["schemaVersion"] = 2
        }

        assertBundleError(
            manifestURL,
            equals: .unsupportedSchemaVersion(2)
        )
    }

    func testRejectsPathOutsideResourceRoot() throws {
        let outsideURL = temporaryDirectory.appendingPathComponent("outside.lzc")
        try lzcData(version: 1).write(to: outsideURL)
        let manifestURL = try makeValidFixture { manifest in
            var lenses = manifest["lenses"] as! [[String: Any]]
            lenses[0]["file"] = "../outside.lzc"
            lenses[0]["sha256"] = self.sha256(try! Data(contentsOf: outsideURL))
            manifest["lenses"] = lenses
        }

        assertBundleError(
            manifestURL,
            equals: .pathEscapesResourceRoot("../outside.lzc")
        )
    }

    func testRejectsMissingPrimaryPackage() throws {
        let manifestURL = try makeValidFixture { manifest in
            var lenses = manifest["lenses"] as! [[String: Any]]
            lenses[0]["file"] = "lenses/missing.lzc"
            manifest["lenses"] = lenses
        }

        assertBundleError(
            manifestURL,
            equals: .missingFile("lenses/missing.lzc")
        )
    }

    func testRejectsPrimaryHashMismatch() throws {
        let manifestURL = try makeValidFixture { manifest in
            var lenses = manifest["lenses"] as! [[String: Any]]
            lenses[0]["sha256"] = String(repeating: "0", count: 64)
            manifest["lenses"] = lenses
        }

        assertHashMismatch(manifestURL, path: "lenses/one.lzc")
    }

    func testRejectsDependencyHashMismatch() throws {
        let manifestURL = try makeValidFixture { manifest in
            var assets = manifest["assets"] as! [[String: Any]]
            assets[0]["sha256"] = String(repeating: "0", count: 64)
            manifest["assets"] = assets
        }

        assertHashMismatch(manifestURL, path: "dependencies/shared.lzc")
    }

    func testRejectsUnsupportedLZCVersion() throws {
        let packageURL = resourceRoot.appendingPathComponent("lenses/one.lzc")
        let unsupported = lzcData(version: 3)
        let manifestURL = try makeValidFixture { manifest in
            try! unsupported.write(to: packageURL)
            var lenses = manifest["lenses"] as! [[String: Any]]
            lenses[0]["sha256"] = self.sha256(unsupported)
            manifest["lenses"] = lenses
        }

        assertBundleError(
            manifestURL,
            equals: .unsupportedLZCVersion(path: "lenses/one.lzc", version: 3)
        )
    }

    func testRejectsConflictingDuplicateDependency() throws {
        let manifestURL = try makeValidFixture { manifest in
            var assets = manifest["assets"] as! [[String: Any]]
            var duplicate = assets[0]
            duplicate["contentURL"] = "https://example.com/different.lzc"
            assets.append(duplicate)
            manifest["assets"] = assets
        }

        assertBundleError(
            manifestURL,
            equals: .conflictingAssetID("asset-shared")
        )
    }

    func testRejectsDuplicateLensID() throws {
        let manifestURL = try makeValidFixture { manifest in
            var lenses = manifest["lenses"] as! [[String: Any]]
            lenses[1]["id"] = "lens-one"
            manifest["lenses"] = lenses
        }

        assertBundleError(
            manifestURL,
            equals: .duplicateLensID("lens-one")
        )
    }

    func testRejectsMissingReferencedAsset() throws {
        let manifestURL = try makeValidFixture { manifest in
            var lenses = manifest["lenses"] as! [[String: Any]]
            lenses[0]["assetIDs"] = ["asset-missing"]
            manifest["lenses"] = lenses
        }

        assertBundleError(
            manifestURL,
            equals: .missingAsset("asset-missing")
        )
    }

    func testRejectsUnexpectedRuntimeAssetValues() throws {
        let manifestURL = try makeValidFixture { manifest in
            var assets = manifest["assets"] as! [[String: Any]]
            assets[0]["assetTiming"] = 5
            manifest["assets"] = assets
        }

        assertBundleError(
            manifestURL,
            equals: .invalidAssetMetadata(id: "asset-shared", assetType: 7, assetTiming: 5)
        )
    }

    func testRejectsMalformedLZCHeader() throws {
        let packageURL = resourceRoot.appendingPathComponent("lenses/one.lzc")
        let malformed = Data("not-an-lzc".utf8)
        let manifestURL = try makeValidFixture { manifest in
            try! malformed.write(to: packageURL)
            var lenses = manifest["lenses"] as! [[String: Any]]
            lenses[0]["sha256"] = self.sha256(malformed)
            manifest["lenses"] = lenses
        }

        assertBundleError(
            manifestURL,
            equals: .invalidLZCHeader("lenses/one.lzc")
        )
    }

    func testRejectsInvalidGroupID() throws {
        let manifestURL = try makeValidFixture { manifest in
            manifest["group"] = ["id": "  ", "name": "Local Test"]
        }

        assertBundleError(
            manifestURL,
            equals: .invalidGroupID("  ")
        )
    }

    func testAcceptsSharedDependencyReferencedByTwoLenses() throws {
        let manifestURL = try makeValidFixture()

        let bundle = try LocalLensBundle(
            manifestURL: manifestURL,
            resourceRootURL: resourceRoot
        )

        XCTAssertEqual(bundle.groupID, "test.local")
        XCTAssertEqual(bundle.groupName, "Local Test")
        XCTAssertEqual(bundle.lensCount, 2)
        XCTAssertEqual(bundle.validatedAssetCount, 1)
    }

    func testBuildsRuntimeExtensionFromValidatedManifest() throws {
        let manifestURL = try makeValidFixture()

        let bundle = try LocalLensBundle(
            manifestURL: manifestURL,
            resourceRootURL: resourceRoot
        )
        let runtime = try XCTUnwrap(
            bundle.initializationExtension as? SCCameraKitLocalLensRuntimeExtension
        )

        XCTAssertEqual(runtime.groupIdentifier, "test.local")
        XCTAssertEqual(runtime.lenses.count, 2)
    }

    func testDefaultCarouselImageLoaderReadsFileURL() throws {
        let imageURL = temporaryDirectory.appendingPathComponent("carousel-icon.png")
        let png = try XCTUnwrap(
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
        )
        try png.write(to: imageURL)
        let completion = expectation(description: "Local carousel icon loaded")
        let loader = DefaultCarouselImageLoader()
        var loadedImage: UIImage?
        var loadedError: Error?

        loader.loadImage(
            url: imageURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            queue: .main
        ) { image, error in
            loadedImage = image
            loadedError = error
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2)
        XCTAssertNotNil(loadedImage)
        XCTAssertNil(loadedError)
    }

    func testLocalCarouselImageBypassesURLSession() throws {
        let imageURL = temporaryDirectory.appendingPathComponent("offline-carousel-icon.png")
        let png = try XCTUnwrap(
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
        )
        try png.write(to: imageURL)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RejectingURLProtocol.self]
        let loader = DefaultCarouselImageLoader(urlSession: URLSession(configuration: configuration))
        let completion = expectation(description: "Local icon loaded without URLSession")
        var loadedImage: UIImage?
        var loadedError: Error?

        loader.loadImage(
            url: imageURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            queue: .main
        ) { image, error in
            loadedImage = image
            loadedError = error
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2)
        XCTAssertNotNil(loadedImage)
        XCTAssertNil(loadedError)
    }

    private func makeValidFixture(
        mutate: ((inout [String: Any]) throws -> Void)? = nil
    ) throws -> URL {
        let lensesDirectory = resourceRoot.appendingPathComponent("lenses", isDirectory: true)
        let dependenciesDirectory = resourceRoot.appendingPathComponent("dependencies", isDirectory: true)
        let iconsDirectory = resourceRoot.appendingPathComponent("icons", isDirectory: true)
        for directory in [lensesDirectory, dependenciesDirectory, iconsDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let lensOne = lzcData(version: 1, payload: 1)
        let lensTwo = lzcData(version: 2, payload: 2)
        let sharedAsset = lzcData(version: 1, payload: 3)
        try lensOne.write(to: lensesDirectory.appendingPathComponent("one.lzc"))
        try lensTwo.write(to: lensesDirectory.appendingPathComponent("two.lzc"))
        try sharedAsset.write(to: dependenciesDirectory.appendingPathComponent("shared.lzc"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: iconsDirectory.appendingPathComponent("icon.png"))

        let asset: [String: Any] = [
            "id": "asset-shared",
            "file": "dependencies/shared.lzc",
            "sha256": sha256(sharedAsset),
            "contentURL": "https://example.com/shared.lzc",
            "assetType": 7,
            "assetTiming": 6,
        ]
        let lenses: [[String: Any]] = [
            lens(
                id: "lens-one",
                name: "Lens One",
                file: "lenses/one.lzc",
                sha256: sha256(lensOne)
            ),
            lens(
                id: "lens-two",
                name: "Lens Two",
                file: "lenses/two.lzc",
                sha256: sha256(lensTwo)
            ),
        ]
        var manifest: [String: Any] = [
            "schemaVersion": 1,
            "group": ["id": "test.local", "name": "Local Test"],
            "assets": [asset],
            "lenses": lenses,
        ]
        try mutate?(&manifest)

        let manifestURL = resourceRoot.appendingPathComponent("manifest.json")
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)
        return manifestURL
    }

    private func lens(id: String, name: String, file: String, sha256: String) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "file": file,
            "sha256": sha256,
            "contentURL": "https://example.com/\(id).lzc",
            "iconFile": "icons/icon.png",
            "facingPreference": 0,
            "assetIDs": ["asset-shared"],
        ]
    }

    private func lzcData(version: UInt32, payload: UInt8 = 0) -> Data {
        var version = version.littleEndian
        var data = Data([0x4C, 0x5A, 0x43, 0x00])
        withUnsafeBytes(of: &version) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined()
    }

    private func assertBundleError(
        _ manifestURL: URL,
        equals expected: LocalLensBundleError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try LocalLensBundle(manifestURL: manifestURL, resourceRootURL: resourceRoot),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? LocalLensBundleError, expected, file: file, line: line)
        }
    }

    private func assertHashMismatch(
        _ manifestURL: URL,
        path: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try LocalLensBundle(manifestURL: manifestURL, resourceRootURL: resourceRoot),
            file: file,
            line: line
        ) { error in
            guard case let .hashMismatch(actualPath, _, _)? = error as? LocalLensBundleError else {
                XCTFail("Expected hash mismatch, received \(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(actualPath, path, file: file, line: line)
        }
    }
}
