#if ENABLE_SPARKLE
import Sparkle
import SwiftUI

/// A wrapper around SPUUpdater for SwiftUI integration.
/// For menu bar apps, we disable automatic background checks to avoid
/// the "gentle reminders" requirement. Updates are checked when user opens menu.
@MainActor
@Observable
final class SparkleUpdater {
    /// The underlying Sparkle updater controller (nil if bundle is invalid)
    private var controller: SPUStandardUpdaterController?

    /// Whether an update is available (for showing badge)
    private(set) var updateAvailable = false

    /// Whether the updater is available (bundle is properly configured)
    var isAvailable: Bool {
        controller != nil
    }

    /// Whether updates can be checked (updater is configured and ready)
    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    /// The date of the last update check
    var lastUpdateCheckDate: Date? {
        controller?.updater.lastUpdateCheckDate
    }

    init() {
        guard Self.isProperAppBundle() else {
            print("SparkleUpdater: Not running from app bundle, updater disabled")
            return
        }

        // Initialize Sparkle WITHOUT starting automatic checks
        // This avoids the "gentle reminders" warning for menu bar apps
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Disable automatic background checks - we'll check manually
        controller?.updater.automaticallyChecksForUpdates = false
    }

    /// Start the updater (call when app is ready)
    func start() {
        controller?.startUpdater()
    }

    /// Manually check for updates (shows UI)
    func checkForUpdates() {
        guard let controller = controller, controller.updater.canCheckForUpdates else {
            return
        }
        controller.checkForUpdates(nil)
    }

    /// Check for updates silently when menu opens
    /// Only shows UI if an update is found
    func checkForUpdatesInBackground() {
        guard let updater = controller?.updater, updater.canCheckForUpdates else {
            return
        }
        updater.checkForUpdatesInBackground()
    }

    /// Check if running from a proper .app bundle
    private static func isProperAppBundle() -> Bool {
        let bundle = Bundle.main

        guard bundle.bundlePath.hasSuffix(".app") else {
            return false
        }

        guard let info = bundle.infoDictionary,
              info["CFBundleIdentifier"] != nil,
              info["CFBundleVersion"] != nil,
              info["SUFeedURL"] != nil else {
            return false
        }

        return true
    }
}

// MARK: - SwiftUI Environment

/// Environment key for accessing the SparkleUpdater
private struct SparkleUpdaterKey: EnvironmentKey {
    static let defaultValue: SparkleUpdater? = nil
}

extension EnvironmentValues {
    @MainActor
    var sparkleUpdater: SparkleUpdater? {
        get { self[SparkleUpdaterKey.self] }
        set { self[SparkleUpdaterKey.self] = newValue }
    }
}
#endif
