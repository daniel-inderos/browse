import Foundation
import Observation

@Observable
final class PrivacySettingsManager: @unchecked Sendable {
    static let shared = PrivacySettingsManager()

    static let privateGoogleS2FaviconFallbackKey = "privacy.privateGoogleS2FaviconFallbackEnabled"
    static let privateBriefingImageLoadingKey = "privacy.privateBriefingImageLoadingEnabled"

    var allowsGoogleS2FaviconFallbackInPrivateBrowsing: Bool {
        didSet {
            guard allowsGoogleS2FaviconFallbackInPrivateBrowsing != oldValue else { return }
            UserDefaults.standard.set(
                allowsGoogleS2FaviconFallbackInPrivateBrowsing,
                forKey: Self.privateGoogleS2FaviconFallbackKey
            )
        }
    }

    var allowsBriefingImageLoadingInPrivateBrowsing: Bool {
        didSet {
            guard allowsBriefingImageLoadingInPrivateBrowsing != oldValue else { return }
            UserDefaults.standard.set(
                allowsBriefingImageLoadingInPrivateBrowsing,
                forKey: Self.privateBriefingImageLoadingKey
            )
        }
    }

    private init() {
        self.allowsGoogleS2FaviconFallbackInPrivateBrowsing = UserDefaults.standard.bool(
            forKey: Self.privateGoogleS2FaviconFallbackKey
        )
        self.allowsBriefingImageLoadingInPrivateBrowsing = UserDefaults.standard.bool(
            forKey: Self.privateBriefingImageLoadingKey
        )
    }
}
