//  Copyright Snap Inc. All rights reserved.
//  CameraKit

import UIKit

@objc(SCCameraKitReferenceUILocalizationBundleStub) class Stub: NSObject {}

/// Objective-C interface for CameraKitLocalizedString
/// - Parameters:
///   - key: key to lookup.
///   - bundle: explicit bundle to look up key for. If omitted, uses the CameraKit Reference UI bundle.
///   - preferredLanguages: a list of language codes in order of preference.
///   - comment: any comments on the string.
///   - table: an explicit strings table to reference.
/// - Returns: a localized string, if one is available for the languages specified, otherwise the English string (and the key, if neither are found).
@objc
public extension NSString {
    @objc
    class func cameraKit_localized(
        key: String,
        bundle: Bundle?,
        preferredLanguages: [String] = NSLocale.preferredLanguages,
        comment: String?,
        table: String? = nil
    ) -> String {
        CameraKitLocalizedString(
            key: key, bundle: bundle, preferredLanguages: preferredLanguages, comment: comment, table: table
        )
    }
}

/// Looks up a localized string for CameraKit's reference UI.
/// - Parameters:
///   - key: key to lookup.
///   - bundle: explicit bundle to look up key for. If omitted, uses the CameraKit Reference UI bundle.
///   - preferredLanguages: a list of language codes in order of preference.
///   - comment: any comments on the string.
///   - table: an explicit strings table to reference.
/// - Returns: a localized string, if one is available for the languages specified, otherwise the English string (and the key, if neither are found).
public func CameraKitLocalizedString(
    key: String,
    bundle: Bundle? = nil,
    preferredLanguages: [String] = NSLocale.preferredLanguages,
    comment: String?,
    table: String? = nil
) -> String {
    let resolvedBundle = bundle ?? bestBundle(forPreferredLanguages: preferredLanguages)
    let fallbackBundle = bestBundle(forPreferredLanguages: ["en-US"])
    let resolvedString = resolvedBundle.localizedString(forKey: key, value: nil, table: table)
    let fallbackString = fallbackBundle.localizedString(forKey: key, value: nil, table: table)
    if resolvedString == key, fallbackString != key {
        // The localizedString call for the specified bundle returned the key (ie: it hasn't been localized) but the English bundle doesn't.
        // This indicates that the requested string has not been localized, and we should fall back to the English value instead of showing the user the key.
        return fallbackString
    }
    if resolvedString == key {
        return Constants.englishFallbacks[key] ?? resolvedString
    }
    return resolvedString
}

private func bestBundle(forPreferredLanguages preferredLanguages: [String]) -> Bundle {
    preferredLanguages.lazy.compactMap(bestBundle(forPreferredLanguage:)).first ?? Bundle(for: Stub.self)
}

private func bestBundle(forPreferredLanguage preferredLanguage: String) -> Bundle? {
    let bundle: Bundle
    #if SWIFT_PACKAGE
        bundle = BundleHelper.resourcesBundle
    #else
    // CocoaPods places it here
    if let url = Bundle.main.url(forResource: "CameraKitReferenceUI", withExtension: "bundle"), let referenceBundle = Bundle(url: url) {
        bundle = referenceBundle
    } else {
        bundle = Bundle(for: Stub.self)
    }
    #endif
    let lProjURL: URL?
    if let fullMatch = bundle.url(forResource: preferredLanguage, withExtension: Constants.lProjExtension) {
        lProjURL = fullMatch
    } else if let fullMatch = bundle.url(
        forResource: preferredLanguage,
        withExtension: Constants.lProjExtension,
        subdirectory: Constants.stringsDirectory
    ) {
        lProjURL = fullMatch
    } else {
        // preferred language contains region code (ie. `es-US`) which may not have its own localization
        // so if not found, try to find localization for just the language code (ie. `es`)
        let components = NSLocale.components(fromLocaleIdentifier: preferredLanguage)
        if let languageCode = components[NSLocale.Key.languageCode.rawValue] {
            lProjURL = bundle.url(forResource: languageCode, withExtension: Constants.lProjExtension)
                ?? bundle.url(
                    forResource: languageCode,
                    withExtension: Constants.lProjExtension,
                    subdirectory: Constants.stringsDirectory
                )
        } else {
            lProjURL = nil
        }
    }
    guard let lProjURL else {
        return nil
    }
    return Bundle(url: lProjURL)
}

private enum Constants {
    static let lProjExtension = "lproj"
    static let stringsDirectory = "Strings"
    static let englishFallbacks = [
        "camera_kit_adjustment_active": "Active",
        "camera_kit_adjustment_intensity_slider": "Adjustment Intensity Slider",
        "camera_kit_adjustment_portrait": "Portrait",
        "camera_kit_adjustment_tone": "Tone",
        "camera_kit_camera_flip_button": "Camera Flip Button",
        "camera_kit_flash_configuration_button": "Flash Configuration Button",
        "camera_kit_flash_toggle_button": "Flash Toggle Button",
        "camera_kit_portrait_adjustment_toggle_button": "Portrait Adjustment Toggle Button",
        "camera_kit_portrait_adjustment_configuration_button": "Portrait Adjustment Configuration Button",
        "camera_kit_tone_map_adjustment_toggle_button": "Tone Map Adjustment Toggle Button",
        "camera_kit_tone_map_configuration_button": "Tone Map Adjustment Configuration Button",
        "camera_kit_flash_control": "Flash Control",
        "camera_kit_portrait_control": "Portrait Control",
        "camera_kit_tone_map_control": "Tone Map Control",
        "camera_kit_connected_lenses_cancel": "Cancel",
        "camera_kit_connected_lenses_group_id": "Group ID",
        "camera_kit_connected_lenses_join_failed_message": "Failed to join connected lenses session, please try again later.",
        "camera_kit_connected_lenses_join_failed_title": "Error",
        "camera_kit_connected_lenses_join_session_message": "Join a session with a group ID.",
        "camera_kit_connected_lenses_join_session_title": "Connected Lenses",
        "camera_kit_connected_lenses_join": "Join",
        "camera_kit_connected_lenses_launch": "Launch",
        "camera_kit_connected_lenses_launch_failed_message": "Failed to launch connected lenses session, please try again later.",
        "camera_kit_connected_lenses_launch_failed_title": "Error",
        "camera_kit_connected_lenses_ok": "Ok",
        "camera_kit_connected_lenses_scan_qr_hint": "Point camera at QR code",
        "camera_kit_connected_lenses_session_id_copied": "Session ID copied to clipboard",
        "camera_kit_connected_lenses_session_qr_title": "Session QR Code",
        "camera_kit_connected_lenses_start": "Start",
        "camera_kit_flash": "Flash",
        "camera_kit_flash_mode_selector": "Flash Mode Selector",
        "camera_kit_ring": "Ring",
        "camera_kit_ring_light_color_selector": "Ring Light Color Selector",
        "camera_kit_ring_light_intensity_slider": "Ring Light Intensity Slider",
        "camera_kit_standard": "Standard",
        "camera_kit_tap_to_dismiss": "Tap anywhere to dismiss",
        "camera_kit_no_media_found": "No Media Found",
        "camera_kit_powered_by": "Powered by",
        "camera_kit_powered_by_snapchat": "Powered by Snapchat",
    ]
}
