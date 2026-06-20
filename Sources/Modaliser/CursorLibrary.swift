import AppKit
import LispKit
import CoreGraphics
import QuartzCore

/// Parses hex colour strings for the cursor highlight ring.
enum CursorColor {
    /// Accepts "#RRGGBB", "RRGGBB", "#RGB", or "RGB". Returns nil on bad input.
    static func parse(_ hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        let chars = Array(s)
        let r: Int, g: Int, b: Int
        switch chars.count {
        case 3:
            guard let rr = Int(String([chars[0], chars[0]]), radix: 16),
                  let gg = Int(String([chars[1], chars[1]]), radix: 16),
                  let bb = Int(String([chars[2], chars[2]]), radix: 16) else { return nil }
            r = rr; g = gg; b = bb
        case 6:
            guard let rr = Int(String(chars[0...1]), radix: 16),
                  let gg = Int(String(chars[2...3]), radix: 16),
                  let bb = Int(String(chars[4...5]), radix: 16) else { return nil }
            r = rr; g = gg; b = bb
        default:
            return nil
        }
        return NSColor(srgbRed: CGFloat(r) / 255.0,
                       green: CGFloat(g) / 255.0,
                       blue: CGFloat(b) / 255.0,
                       alpha: 1.0)
    }
}

/// Resolved parameters for one highlight flash.
struct CursorHighlightOptions {
    var color: NSColor
    var size: CGFloat
    var thickness: CGFloat
    var glow: CGFloat
    var duration: Double
    var nudge: Bool

    /// Defaults per the spec.
    static var defaults: CursorHighlightOptions {
        CursorHighlightOptions(
            color: CursorColor.parse("#FFCC33") ?? .systemYellow,
            size: 240, thickness: 6, glow: 18, duration: 0.45, nudge: true
        )
    }

    /// Extract a Double from a Scheme number (fixnum or flonum), else nil.
    static func number(_ e: Expr) -> Double? {
        switch e {
        case .fixnum(let n): return Double(n)
        case .flonum(let d): return d
        default: return nil
        }
    }

    /// Interpret keyword pairs into options, parsing each value exactly once.
    /// Any ignored input — an unparseable colour, a non-numeric numeric arg, or
    /// an unknown keyword — leaves the corresponding default in place and adds
    /// one warning, so the caller can surface typos. `nudge` accepts any value
    /// (Scheme truthiness: only `#f` is false), so it never warns.
    static func parse(_ pairs: [(String, Expr)])
        -> (options: CursorHighlightOptions, warnings: [String]) {
        var o = CursorHighlightOptions.defaults
        var warnings: [String] = []
        for (key, value) in pairs {
            switch key {
            case "color":
                if let s = try? value.asString() {
                    if let c = CursorColor.parse(s) { o.color = c }
                    else { warnings.append("ignoring invalid 'color' \"\(s)\"") }
                } else {
                    warnings.append("ignoring non-string 'color' value")
                }
            case "size":      if let n = number(value) { o.size = CGFloat(n) } else { warnings.append("ignoring non-numeric 'size' value") }
            case "thickness": if let n = number(value) { o.thickness = CGFloat(n) } else { warnings.append("ignoring non-numeric 'thickness' value") }
            case "glow":      if let n = number(value) { o.glow = CGFloat(n) } else { warnings.append("ignoring non-numeric 'glow' value") }
            case "duration":  if let n = number(value) { o.duration = n } else { warnings.append("ignoring non-numeric 'duration' value") }
            case "nudge":     if case .false = value { o.nudge = false } else { o.nudge = true }
            default:          warnings.append("ignoring unknown option '\(key)'")
            }
        }
        return (o, warnings)
    }
}

/// Owns the reusable overlay panel and runs the highlight animation.
/// All methods must be called on the main thread.
final class CursorHighlightController {
    private var panel: NSPanel?
    private var generation = 0

    func flash(_ options: CursorHighlightOptions) {
        // Capture cursor position BEFORE nudging (nudge nets zero displacement).
        let center = NSEvent.mouseLocation  // global cocoa coords, bottom-left origin

        if options.nudge { Self.nudgeMouse() }

        // Panel sized so the glow blur + stroke are never clipped.
        let pad = options.glow + options.thickness
        let side = options.size + 2 * pad
        let frame = NSRect(x: center.x - side / 2, y: center.y - side / 2,
                           width: side, height: side)

        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        panel.setFrame(frame, display: false)

        guard let host = panel.contentView, let hostLayer = host.layer else { return }
        host.frame = NSRect(origin: .zero, size: frame.size)
        hostLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        // Ring layer fills the host; the circular path is inset by `pad`.
        let ring = CAShapeLayer()
        ring.frame = hostLayer.bounds
        let ringRect = CGRect(x: pad, y: pad, width: options.size, height: options.size)
        ring.path = CGPath(ellipseIn: ringRect, transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = options.color.cgColor
        ring.lineWidth = options.thickness
        ring.shadowColor = options.color.cgColor   // colour-matched "neon" glow
        ring.shadowRadius = options.glow
        ring.shadowOpacity = 1.0
        ring.shadowOffset = .zero
        ring.masksToBounds = false
        hostLayer.addSublayer(ring)

        panel.orderFrontRegardless()

        // Converge (scale large -> small about the centre) + fade near the end.
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 0.15
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1.0, 1.0, 0.0]
        fade.keyTimes = [0.0, 0.6, 1.0]
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = options.duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards

        generation += 1
        let myGen = generation
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak panel] in
            // Only hide if no newer flash has started.
            if self?.generation == myGen { panel?.orderOut(nil) }
        }
        ring.add(group, forKey: "converge")
        CATransaction.commit()
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        let host = NSView()
        host.wantsLayer = true
        host.layer?.masksToBounds = false
        p.contentView = host
        return p
    }

    /// Move the cursor +1px then back, posting real mouseMoved events so a
    /// cursor hidden by idle timeout reappears. Net displacement is zero.
    private static func nudgeMouse() {
        let cocoa = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let ax = CGPoint(x: cocoa.x, y: primaryHeight - cocoa.y)  // CGEvent uses top-left origin
        let moved = CGPoint(x: ax.x + 1, y: ax.y)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: moved, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: ax, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}

/// Native LispKit library providing the cursor highlight.
/// Scheme name: (modaliser cursor)
///
/// Provides: highlight-cursor
final class CursorLibrary: NativeLibrary {
    private let controller = CursorHighlightController()

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "cursor"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define")
    }

    public override func declarations() {
        self.define(Procedure("highlight-cursor", highlightCursorFunction))
    }

    /// (highlight-cursor ['color hex] ['size px] ['thickness px]
    ///                   ['glow px] ['duration secs] ['nudge bool]) -> void
    private func highlightCursorFunction(_ args: Arguments) throws -> Expr {
        let exprs = Array(args)
        var pairs: [(String, Expr)] = []
        var i = 0
        while i < exprs.count {
            if case .symbol(let sym) = exprs[i], i + 1 < exprs.count {
                pairs.append((sym.identifier, exprs[i + 1]))
                i += 2
            } else {
                i += 1
            }
        }
        // Parse once; surface every ignored option (typo'd colour, non-numeric
        // arg, unknown keyword) as a warning. Never throws.
        let (options, warnings) = CursorHighlightOptions.parse(pairs)
        for w in warnings {
            NSLog("highlight-cursor: %@", w)
        }
        DispatchQueue.main.async { [controller] in
            controller.flash(options)
        }
        return .void
    }
}
