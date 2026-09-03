import AppKit
import CoreGraphics
import Domain
import Infrastructure

// MARK: - Persistent Touch Bar Driver

/// Manages an always-on, system-wide Touch Bar interface inspired by `tpklo/claude-usage-touchbar`.
/// Uses macOS system modal presentation (placement 0) so it remains visible across all applications and windows.
@MainActor
public final class PersistentTouchBarDriver: NSObject, NSTouchBarDelegate {
    public static let shared = PersistentTouchBarDriver()

    private let sceneId = NSTouchBarItem.Identifier("com.tddworks.claudebar.touchbar.scene")
    private let escId = NSTouchBarItem.Identifier("com.tddworks.claudebar.touchbar.esc")

    private var touchBar: NSTouchBar?
    private var petView: ClaudePetTouchBarView?
    private var monitor: QuotaMonitor?
    private var settings: AppSettings?

    private var sync: ObservationRenderSync<[TouchBarProviderGauge]>?
    private var isPresented = false
    private var activateObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?

    public override init() {
        super.init()
    }

    public func configure(monitor: QuotaMonitor, settings: AppSettings) {
        self.monitor = monitor
        self.settings = settings
    }

    public func start() {
        guard self.monitor != nil, self.settings != nil, sync == nil else { return }

        // 1. Build View and TouchBar
        let view = ClaudePetTouchBarView(frame: NSRect(x: 0, y: 0, width: ClaudePetTouchBarView.sceneW, height: ClaudePetTouchBarView.sceneH))
        self.petView = view

        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [sceneId]
        bar.escapeKeyReplacementItemIdentifier = escId
        self.touchBar = bar

        // 2. Continuous State Sync
        let newSync = ObservationRenderSync(
            read: { [self] in buildGauges() },
            render: { [self] gauges in updateGauges(gauges) }
        )
        self.sync = newSync
        newSync.start()

        // 3. Re-assert on application switch (cheap and idempotent)
        activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.presentIfNeeded()
            }
        }

        // 4. Re-assert when screen unlocks
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.presentIfNeeded()
            }
        }

        presentIfNeeded()
    }

    public func stop() {
        dismiss()
        sync?.stop()
        sync = nil
        petView?.stopAnimation()
        petView = nil
        touchBar = nil

        if let activateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateObserver)
            self.activateObserver = nil
        }
        if let unlockObserver {
            DistributedNotificationCenter.default().removeObserver(unlockObserver)
            self.unlockObserver = nil
        }
    }

    // MARK: - State Observation

    private func buildGauges() -> [TouchBarProviderGauge] {
        guard let monitor, let settings, settings.touchBarEnabled else {
            return []
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

        var gauges: [TouchBarProviderGauge] = []

        if let label, !label.segments.isEmpty {
            for seg in label.segments {
                let pid = resolveProviderId(forSegmentText: seg.text)
                let name = resolveProviderName(forId: pid, fallbackText: seg.text)
                let pct = parsePercentage(from: seg.text)
                let resetText = parseResetText(from: seg.text)

                gauges.append(TouchBarProviderGauge(
                    providerId: pid,
                    name: name,
                    percentUsed: pct,
                    resetText: resetText,
                    status: seg.status
                ))
            }
        } else if let selected = monitor.selectedProvider {
            let pid = selected.id
            let pct: Double
            if let lowest = selected.snapshot?.lowestQuota {
                pct = Double(lowest.percentUsed)
            } else {
                pct = 0
            }
            let resetText: String?
            if let resetsAt = selected.snapshot?.lowestQuota?.resetsAt {
                let diff = Int(resetsAt.timeIntervalSinceNow)
                if diff > 0 {
                    let h = diff / 3600
                    let m = (diff % 3600) / 60
                    resetText = h > 0 ? "\(h)h\(m)m" : "\(m)m"
                } else {
                    resetText = nil
                }
            } else {
                resetText = nil
            }

            gauges.append(TouchBarProviderGauge(
                providerId: pid,
                name: selected.name,
                percentUsed: pct,
                resetText: resetText,
                status: selected.snapshot?.overallStatus ?? .healthy
            ))
        }

        return gauges
    }

    private func resolveProviderId(forSegmentText text: String) -> String {
        guard let monitor, let settings else { return "claude" }
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

    private func resolveProviderName(forId id: String, fallbackText: String) -> String {
        if let provider = monitor?.provider(for: id) {
            return provider.name
        }
        // Extract words before numbers
        let parts = fallbackText.split(separator: " ")
        if let first = parts.first {
            return String(first)
        }
        return id.capitalized
    }

    private func parsePercentage(from text: String) -> Double {
        // Find percentage like "62%" in "Gemini 62%"
        if let pctRange = text.range(of: #"(\d+)%"#, options: .regularExpression) {
            let numStr = text[pctRange].dropLast()
            if let val = Double(numStr) {
                return max(0, min(100, val))
            }
        }
        return 0
    }

    private func parseResetText(from text: String) -> String? {
        // Look for duration pattern like "· 2h15" or "45m"
        if let dotRange = text.range(of: "· ") {
            return String(text[dotRange.upperBound...])
        }
        return nil
    }

    private func updateGauges(_ gauges: [TouchBarProviderGauge]) {
        petView?.gauges = gauges

        if let settings, settings.touchBarEnabled, !gauges.isEmpty {
            presentIfNeeded()
        } else {
            dismiss()
        }
    }

    // MARK: - System Modal Presentation

    public func presentIfNeeded() {
        guard let touchBar, let settings, settings.touchBarEnabled else { return }

        // Hide close box so it runs as an unobtrusive persistent bar
        typealias CloseBoxFunc = @convention(c) (Bool) -> Void
        if let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW) {
            if let sym = dlsym(dfr, "DFRSystemModalShowsCloseBoxWhenFrontMost") {
                let fn = unsafeBitCast(sym, to: CloseBoxFunc.self)
                fn(false)
            }
            dlclose(dfr)
        }

        typealias PresentModalFunc = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, NSString?) -> Void
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        if let method = class_getClassMethod(NSTouchBar.self, sel) {
            let imp = method_getImplementation(method)
            let presentModal = unsafeBitCast(imp, to: PresentModalFunc.self)
            presentModal(NSTouchBar.self, sel, touchBar, 0, nil)
            isPresented = true
        }
    }

    public func dismiss() {
        guard let touchBar, isPresented else { return }

        typealias DismissModalFunc = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        if let method = class_getClassMethod(NSTouchBar.self, sel) {
            let imp = method_getImplementation(method)
            let dismissModal = unsafeBitCast(imp, to: DismissModalFunc.self)
            dismissModal(NSTouchBar.self, sel, touchBar)
            isPresented = false
        }
    }

    // MARK: - NSTouchBarDelegate

    public func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == sceneId, let petView {
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = petView
            return item
        } else if identifier == escId {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let btn = NSButton(title: "esc", target: self, action: #selector(sendEscape))
            btn.bezelColor = .controlColor
            item.view = btn
            return item
        }
        return nil
    }

    @objc private func sendEscape() {
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
           let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
