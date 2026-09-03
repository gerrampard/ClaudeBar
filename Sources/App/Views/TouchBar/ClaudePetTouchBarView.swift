import AppKit
import CoreGraphics
import Domain
import Infrastructure

// MARK: - Data Models

public struct TouchBarProviderGauge: Equatable, Sendable {
    public let providerId: String
    public let name: String
    public let percentUsed: Double
    public let resetText: String?
    public let status: QuotaStatus

    public init(
        providerId: String,
        name: String,
        percentUsed: Double,
        resetText: String?,
        status: QuotaStatus
    ) {
        self.providerId = providerId
        self.name = name
        self.percentUsed = percentUsed
        self.resetText = resetText
        self.status = status
    }
}

// MARK: - ClaudePetTouchBarView

/// Interactive Touch Bar view inspired by `tpklo/claude-usage-touchbar`.
/// Renders an animated pixel mascot on the left and live provider usage gauges on the right.
@MainActor
public final class ClaudePetTouchBarView: NSView {
    public static let sceneW: CGFloat = 600.0
    public static let sceneH: CGFloat = 30.0

    private enum Mood {
        case calm, brisk, tired, panic

        static func from(usage: Double) -> Mood {
            if usage >= 85.0 { return .panic }
            if usage >= 60.0 { return .tired }
            if usage >= 30.0 { return .brisk }
            return .calm
        }

        var speed: CGFloat {
            switch self {
            case .calm: return 12.0
            case .brisk: return 24.0
            case .tired: return 8.0
            case .panic: return 48.0
            }
        }
    }

    // Mascot State
    private var x: CGFloat = 40.0
    private var dir: CGFloat = 1.0
    private var phase: CGFloat = 0.0
    private var dragging = false
    private var grabDX: CGFloat = 0.0
    private var dragVX: CGFloat = 0.0
    private var lastDragX: CGFloat = 0.0
    private var throwVX: CGFloat = 0.0
    private var wiggleT: CGFloat = 0.0

    // Gauges
    public var gauges: [TouchBarProviderGauge] = [] {
        didSet {
            cachedIcons = gauges.map { loadProviderIcon(for: $0.providerId) }
            needsDisplay = true
        }
    }
    private var cachedIcons: [NSImage?] = []

    // Frame timer
    private var timer: Timer?
    private var lastTick: TimeInterval = 0

    // Clawd 20x20 base sprite grid
    private static let baseGrid: [UInt8] = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 2, 1, 1, 1, 1, 1, 2, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 0, 0,
        0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0,
        0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0,
        0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ]

    public override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.sceneW, height: Self.sceneH))
        self.allowedTouchTypes = [.direct]
        startAnimation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var isFlipped: Bool { false }
    public override var acceptsFirstResponder: Bool { true }

    public func startAnimation() {
        guard timer == nil else { return }
        lastTick = Date.timeIntervalSinceReferenceDate
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.step()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Animation Step

    private func step() {
        let now = Date.timeIntervalSinceReferenceDate
        let dt = min(0.1, max(0.001, now - lastTick))
        lastTick = now

        let maxUsage = gauges.map(\.percentUsed).max() ?? 0
        let mood = Mood.from(usage: maxUsage)

        let readoutW = min(380.0, CGFloat(max(1, gauges.count)) * 170.0)
        let wall = bounds.width - readoutW - 25.0

        if dragging {
            phase += dt * 17.0
            wiggleT += dt
            needsDisplay = true
            return
        }

        if abs(throwVX) > 1.0 {
            x += throwVX * dt
            throwVX *= 0.92
            let lo: CGFloat = 20.0
            let hi: CGFloat = max(lo + 10, wall)
            if x < lo { x = lo; throwVX = -throwVX * 0.5; dir = 1 }
            if x > hi { x = hi; throwVX = -throwVX * 0.5; dir = -1 }
            phase += dt * (abs(throwVX) / 9.0)
            needsDisplay = true
            return
        }

        // Pacing walk
        x += dir * mood.speed * dt
        let pad: CGFloat = 24.0
        let rightLimit = max(pad + 10, wall)

        if x > rightLimit { x = rightLimit; dir = -1 }
        if x < pad { x = pad; dir = 1 }

        phase += dt * (mood.speed / 9.0)
        needsDisplay = true
    }

    // MARK: - Touch Interaction

    public override func touchesBegan(with event: NSEvent) {
        guard let touch = event.touches(matching: .any, in: self).first else { return }
        let tx = touch.location(in: self).x

        let readoutW = min(380.0, CGFloat(max(1, gauges.count)) * 170.0)
        let readoutX = bounds.width - readoutW - 8.0

        // Tap on readout area -> open ClaudeBar
        if tx >= readoutX {
            NSWorkspace.shared.open(URL(string: "claudebar://open")!)
            return
        }

        // Grab Clawd if close
        if abs(tx - x) < 36.0 {
            dragging = true
            grabDX = tx - x
            dragVX = 0
            lastDragX = tx
        }
    }

    public override func touchesMoved(with event: NSEvent) {
        guard dragging, let touch = event.touches(matching: .any, in: self).first else { return }
        let tx = touch.location(in: self).x
        let nx = tx - grabDX
        dragVX = tx - lastDragX
        lastDragX = tx

        let readoutW = min(380.0, CGFloat(max(1, gauges.count)) * 170.0)
        let wall = bounds.width - readoutW - 25.0
        x = max(20.0, min(nx, wall))

        if abs(dragVX) > 0.5 { dir = (dragVX > 0) ? 1 : -1 }
        needsDisplay = true
    }

    public override func touchesEnded(with event: NSEvent) { releaseDrag() }
    public override func touchesCancelled(with event: NSEvent) { releaseDrag() }

    private func releaseDrag() {
        guard dragging else { return }
        dragging = false
        throwVX = dragVX * 12.0
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill()

        let maxUsage = gauges.map(\.percentUsed).max() ?? 0
        let mood = Mood.from(usage: maxUsage)

        // Ground line across the Touch Bar
        NSColor(white: 1.0, alpha: 0.14).set()
        NSRect(x: 0, y: 1.0, width: bounds.width, height: 1.0).fill()

        drawMascot(mood: mood)
        drawReadout()
    }

    private func drawMascot(mood: Mood) {
        let px: CGFloat = 1.72
        let bob: CGFloat = (mood == .tired) ? 0 : (((Int(phase * 2.0) & 1) == 1) ? 0.7 : 0)
        let feetY: CGFloat = 2.2 + bob
        let feetX: CGFloat = self.x
        let isFlipped = self.dir < 0

        let bodyColor = (mood == .panic)
            ? NSColor(srgbRed: 0.86, green: 0.30, blue: 0.22, alpha: 1.0)
            : NSColor(srgbRed: 0.804, green: 0.498, blue: 0.416, alpha: 1.0)
        let eyeColor = NSColor(srgbRed: 0.06, green: 0.06, blue: 0.06, alpha: 1.0)

        // Panic motion streaks
        if mood == .panic {
            bodyColor.withAlphaComponent(0.28).set()
            for i in 1...3 {
                let sx = feetX - dir * (20.0 * px * 0.4 + CGFloat(i) * 5.0)
                NSRect(x: min(sx, sx - dir * 4.0), y: feetY + 8.0, width: 4.0, height: 1.6).fill()
            }
        }

        // Draw sprite pixels
        let walkStep = Int(phase * 2.0)
        let sprite = Self.walkFrame(step: walkStep)

        for r in 3...17 {
            for c in 0..<20 {
                let v = sprite[r * 20 + c]
                if v == 0 { continue }
                let ink = (v == 2) ? eyeColor : bodyColor
                ink.set()
                let cx = isFlipped ? (19 - c) : c
                let rowUp = CGFloat(17 - r)
                NSRect(
                    x: feetX + (CGFloat(cx) - 10.0) * px,
                    y: feetY + rowUp * px,
                    width: px + 0.4,
                    height: px + 0.4
                ).fill()
            }
        }

        // Tired sweat drop
        if mood == .tired {
            NSColor(srgbRed: 0.42, green: 0.70, blue: 0.94, alpha: 0.95).set()
            NSRect(x: feetX + 8.0, y: feetY + 13.0 * px * 0.9, width: 2.4, height: 3.4).fill()
        }
    }

    private static func walkFrame(step: Int) -> [UInt8] {
        var buf = baseGrid
        for r in 14...16 {
            for c in 0..<20 {
                if buf[r * 20 + c] == 1 { buf[r * 20 + c] = 0 }
            }
        }
        let legX = [5, 8, 12, 15]
        let swing = [
            [-1, 1, -1, 1],
            [0, 0, 0, 0],
            [1, -1, 1, -1],
            [0, 0, 0, 0]
        ]
        let lift = [
            [0, 1, 0, 1],
            [0, 0, 0, 0],
            [1, 0, 1, 0],
            [0, 0, 0, 0]
        ]
        let ph = step & 3
        for i in 0..<4 {
            let c = legX[i] + swing[ph][i]
            if c < 0 || c >= 20 { continue }
            let bottom = (lift[ph][i] == 1) ? 15 : 16
            for r in 14...bottom {
                buf[r * 20 + c] = 1
            }
        }
        return buf
    }

    // MARK: - Readout & Bars

    private func drawReadout() {
        guard !gauges.isEmpty else { return }

        let n = CGFloat(gauges.count)
        let cellGap: CGFloat = 12.0
        let totalReadoutW = min(380.0, max(200.0, n * 170.0 + (n - 1) * cellGap))
        let cellW = (totalReadoutW - cellGap * (n - 1)) / n
        let startX = bounds.width - totalReadoutW - 8.0

        for (i, gauge) in gauges.enumerated() {
            let cx = startX + CGFloat(i) * (cellW + cellGap)
            let icon = (i < cachedIcons.count) ? cachedIcons[i] : nil

            // Draw vertical separator | between cells
            if i > 0 {
                let sepX = cx - cellGap / 2.0
                NSColor(white: 1.0, alpha: 0.25).set()
                NSRect(x: sepX, y: 3.0, width: 1.0, height: 22.0).fill()
            }

            drawGaugeCell(gauge, icon: icon, x: cx, width: cellW)
        }
    }

    private func drawGaugeCell(_ gauge: TouchBarProviderGauge, icon: NSImage?, x: CGFloat, width: CGFloat) {
        let textY: CGFloat = 15.0
        let barY: CGFloat = 3.0
        let barH: CGFloat = 7.0

        let pct = Int(gauge.percentUsed.rounded())
        let alarm = (pct >= 90)

        // Palette matching claude-usage-touchbar
        let ink: NSColor
        if alarm {
            ink = NSColor(srgbRed: 0.902, green: 0.208, blue: 0.180, alpha: 1.0) // #E6352E Alert Red
        } else if pct >= 50 {
            ink = NSColor(srgbRed: 0.949, green: 0.706, blue: 0.161, alpha: 1.0) // #F2B429 Warning Amber
        } else {
            ink = NSColor(srgbRed: 0.173, green: 0.533, blue: 0.945, alpha: 1.0) // #2C88F1 Healthy Blue
        }

        // 1. Draw Provider Icon
        var nameX = x
        let iconRect = NSRect(x: x, y: textY - 1.0, width: 14.0, height: 14.0)
        if let icon {
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(roundedRect: iconRect, xRadius: 3.0, yRadius: 3.0)
            clip.addClip()
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            nameX += 18.0
        } else {
            let symName = ProviderVisualIdentityLookup.symbolIcon(for: gauge.providerId)
            if let sym = NSImage(systemSymbolName: symName, accessibilityDescription: nil) {
                let conf = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
                if let configSym = sym.withSymbolConfiguration(conf) {
                    configSym.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                    nameX += 18.0
                }
            }
        }

        // 2. Draw Provider Name
        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.85)
        ]
        (gauge.name as NSString).draw(at: NSPoint(x: nameX, y: textY), withAttributes: nameAttr)
        let nameW = (gauge.name as NSString).size(withAttributes: nameAttr).width

        // 3. Draw Reset Countdown Note
        if let reset = gauge.resetText, !reset.isEmpty {
            let noteAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.55)
            ]
            (reset as NSString).draw(at: NSPoint(x: nameX + nameW + 5.0, y: textY + 1.0), withAttributes: noteAttr)
        }

        // 4. Draw Percentage + Alarm Right-aligned
        let numStr = alarm ? "\(pct)% !" : "\(pct)%"
        let numAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: ink
        ]
        let numW = (numStr as NSString).size(withAttributes: numAttr).width
        (numStr as NSString).draw(at: NSPoint(x: x + width - numW, y: textY - 1.0), withAttributes: numAttr)

        // 5. Progress Bar Track (100% reference)
        let trackRect = NSRect(x: x, y: barY, width: width, height: barH)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: 2.0, yRadius: 2.0)
        NSColor(white: 1.0, alpha: 0.32).set()
        trackPath.fill()

        // 6. Filled Bar
        let fillW = max(0, min(width, width * CGFloat(pct) / 100.0))
        if fillW > 0 {
            let fillRect = NSRect(x: x, y: barY, width: fillW, height: barH)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2.0, yRadius: 2.0)
            ink.set()
            fillPath.fill()
        }

        // 7. Scale Ticks at 50% and 90%
        NSColor(white: 1.0, alpha: 0.35).set()
        for frac in [0.5, 0.9] {
            let tx = width * frac
            if tx > fillW {
                NSRect(x: x + tx, y: barY, width: 1.0, height: barH).fill()
            }
        }
    }

    private func loadProviderIcon(for providerId: String) -> NSImage? {
        let pid = providerId.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let userPath = home.appendingPathComponent(".claudebar/icons/\(pid).png").path
        if FileManager.default.fileExists(atPath: userPath), let img = NSImage(contentsOfFile: userPath) {
            return img
        }
        let assetName = ProviderVisualIdentityLookup.iconAssetName(for: pid)
        if let img = NSImage(named: assetName) {
            return img
        }
        return nil
    }
}
