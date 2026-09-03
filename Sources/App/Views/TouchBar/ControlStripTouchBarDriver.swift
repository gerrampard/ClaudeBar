import AppKit
import SwiftUI
import Domain
import Infrastructure

// MARK: - Control Strip Touch Bar Driver

/// Drives a persistent Touch Bar widget inside the macOS Control Strip (system tray),
/// ensuring quota status and provider logos stay visible across all applications and windows.
@MainActor
public final class ControlStripTouchBarDriver {
    public static let identifier = NSTouchBarItem.Identifier("com.tddworks.claudebar.touchbar.controlstrip")

    public struct Content: Equatable {
        public struct Segment: Equatable {
            public let providerId: String
            public let text: String
            public let status: QuotaStatus

            public init(providerId: String, text: String, status: QuotaStatus) {
                self.providerId = providerId
                self.text = text
                self.status = status
            }
        }

        public let enabled: Bool
        public let segments: [Segment]

        public init(enabled: Bool, segments: [Segment]) {
            self.enabled = enabled
            self.segments = segments
        }
    }

    private let monitor: QuotaMonitor
    private let settings: AppSettings

    private var sync: ObservationRenderSync<Content>?
    private var trayItem: NSCustomTouchBarItem?
    private var hostingView: NSHostingView<ControlStripTouchBarWidget>?
    private var isRegistered = false

    public init(monitor: QuotaMonitor, settings: AppSettings) {
        self.monitor = monitor
        self.settings = settings
    }

    /// Starts observing state changes and mounts the Control Strip item.
    public func start() {
        guard sync == nil else { return }

        let newSync = ObservationRenderSync(
            read: { [self] in buildContent() },
            render: { [self] content in render(content) }
        )
        sync = newSync
        newSync.start()
    }

    /// Stops observing and removes the Control Strip item.
    public func stop() {
        sync?.stop()
        sync = nil
        unregisterItem()
    }

    // MARK: - State Builder

    private func buildContent() -> Content {
        guard settings.touchBarEnabled else {
            return Content(enabled: false, segments: [])
        }

        let label = monitor.menuBarLabel(
            providerId: settings.menuBarPercentageProviderId,
            primaryQuotaKey: settings.menuBarPercentageQuotaKey,
            secondaryQuotaKey: settings.menuBarSecondaryQuotaKey,
            showPercentage: settings.menuBarPercentageEnabled,
            showDuration: settings.menuBarDurationEnabled,
            mode: settings.usageDisplayMode,
            burnRateWarningEnabled: settings.burnRateWarningEnabled,
            burnRateThreshold: settings.burnRateThreshold
        )

        var segments: [Content.Segment] = []

        if let label, !label.segments.isEmpty {
            for seg in label.segments {
                let pid = resolveProviderId(forSegmentText: seg.text)
                segments.append(Content.Segment(
                    providerId: pid,
                    text: seg.text,
                    status: seg.status
                ))
            }
        } else if let selected = monitor.selectedProvider {
            let pid = selected.id
            let text: String
            if let lowest = selected.snapshot?.lowestQuota {
                let pct = Int(lowest.percentRemaining.rounded())
                text = "\(selected.name) \(pct)%"
            } else {
                text = selected.name
            }
            segments.append(Content.Segment(
                providerId: pid,
                text: text,
                status: selected.snapshot?.overallStatus ?? .healthy
            ))
        }

        return Content(enabled: true, segments: segments)
    }

    private func resolveProviderId(forSegmentText text: String) -> String {
        let lower = text.lowercased()
        for provider in monitor.allProviders {
            let pid = provider.id.lowercased()
            let pname = provider.name.lowercased()
            if lower.contains(pname) || lower.contains(pid) {
                return provider.id
            }
        }
        return settings.menuBarPercentageProviderId
    }

    // MARK: - Renderer

    private func render(_ content: Content) {
        if !content.enabled || content.segments.isEmpty {
            unregisterItem()
            return
        }

        registerItemIfNeeded()

        if let hostingView {
            hostingView.rootView = ControlStripTouchBarWidget(content: content)
            hostingView.invalidateIntrinsicContentSize()
        }
    }

    private func registerItemIfNeeded() {
        guard !isRegistered else { return }

        let item = NSCustomTouchBarItem(identifier: Self.identifier)
        let widget = ControlStripTouchBarWidget(content: buildContent())
        let hosting = NSHostingView(rootView: widget)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        item.view = hosting

        self.hostingView = hosting
        self.trayItem = item

        // Register with Control Strip system tray via private AppKit API
        let addSelector = NSSelectorFromString("addSystemTrayItem:")
        if (NSTouchBarItem.self as AnyObject).responds(to: addSelector) {
            _ = (NSTouchBarItem.self as AnyObject).perform(addSelector, with: item)
        }

        setControlStripPresence(true)
        isRegistered = true
    }

    private func unregisterItem() {
        guard isRegistered, let item = trayItem else { return }

        setControlStripPresence(false)

        let removeSelector = NSSelectorFromString("removeSystemTrayItem:")
        if (NSTouchBarItem.self as AnyObject).responds(to: removeSelector) {
            _ = (NSTouchBarItem.self as AnyObject).perform(removeSelector, with: item)
        }

        self.trayItem = nil
        self.hostingView = nil
        self.isRegistered = false
    }

    private func setControlStripPresence(_ present: Bool) {
        typealias SetPresenceFunc = @convention(c) (CFString, Bool) -> Void
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW) else {
            return
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") else {
            return
        }

        let function = unsafeBitCast(symbol, to: SetPresenceFunc.self)
        function(Self.identifier.rawValue as CFString, present)
    }
}

// MARK: - Persistent Control Strip View

/// Renders real provider logos and quota text in the persistent Touch Bar Control Strip.
public struct ControlStripTouchBarWidget: View {
    let content: ControlStripTouchBarDriver.Content

    public init(content: ControlStripTouchBarDriver.Content) {
        self.content = content
    }

    public var body: some View {
        Button(action: {
            NSWorkspace.shared.open(URL(string: "claudebar://open")!)
        }) {
            HStack(spacing: 6) {
                ForEach(Array(content.segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Text("|")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .padding(.horizontal, 1)
                    }

                    HStack(spacing: 5) {
                        if let logo = loadProviderIcon(for: segment.providerId) {
                            Image(nsImage: logo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 15, height: 15)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: ProviderVisualIdentityLookup.symbolIcon(for: segment.providerId))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(color(for: segment.status))
                        }

                        Text(segment.text)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.14))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func loadProviderIcon(for providerId: String) -> NSImage? {
        let pid = providerId.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let userIconPath = home.appendingPathComponent(".claudebar/icons/\(pid).png").path
        if FileManager.default.fileExists(atPath: userIconPath), let image = NSImage(contentsOfFile: userIconPath) {
            return image
        }

        let assetName = ProviderVisualIdentityLookup.iconAssetName(for: pid)
        if let image = NSImage(named: assetName) {
            return image
        }

        return nil
    }

    private func color(for status: QuotaStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .orange
        case .depleted: return .red
        }
    }
}
