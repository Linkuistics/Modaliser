import AppKit
import LispKit

/// Native LispKit library exposing macOS Accessibility primitives that need
/// to round-trip element references back to Scheme.
/// Scheme name: (modaliser accessibility)
///
/// AXUIElement is a CFTypeRef and not safely convertible to a Scheme value,
/// so we hand out integer handles and keep the element pointers in a Swift
/// dictionary. Each call to ax-find-elements rebuilds the cache — stale
/// handles from a previous call become invalid silently. That's fine for
/// the modal-tree use case where the lifecycle is one-shot:
///   query → display → user picks → click → done.
///
/// The primitives are deliberately *generic*: there's nothing iTerm-specific
/// in this file. App-specific composition (which role to query, where to
/// click within the matched frame) lives in Scheme — see lib/iterm.scm for
/// the iTerm-pane case.
///
/// Provides:
///   (ax-find-elements bundle-id role)
///       Walk the AX tree of bundle-id's focused window, collect every
///       descendant whose AXRole equals role. Returns a list of alists:
///         ((handle . N) (x . N) (y . N) (w . N) (h . N))
///       sorted top-to-bottom, then left-to-right.
///
///   (ax-click-handle handle)
///       Activate the handle's owning app and synthesize a left-click at
///       the centre of the handle's frame. Cursor is saved and warped
///       back. No-op for stale handles.
final class AccessibilityLibrary: NativeLibrary {

    /// Handles only stay valid until the next ax-find-elements call.
    /// Handle 0 is reserved as "invalid".
    private var elementsByHandle: [Int64: AXUIElement] = [:]
    private var nextHandle: Int64 = 1

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "accessibility"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"])
    }

    public override func declarations() {
        self.define(Procedure("ax-find-elements", axFindElementsFunction))
        self.define(Procedure("ax-click-handle", axClickHandleFunction))
    }

    // MARK: - Procedures

    private func axFindElementsFunction(_ bundleIdExpr: Expr,
                                         _ roleExpr: Expr) throws -> Expr {
        let bundleId = try bundleIdExpr.asString()
        let role = try roleExpr.asString()

        // Refresh the cache. This invalidates handles from prior calls; the
        // assumption is that the consumer re-queries each time it needs a
        // fresh layout.
        elementsByHandle.removeAll(keepingCapacity: true)
        nextHandle = 1

        guard let app = runningApp(forBundleId: bundleId) else {
            return .null
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = focusedWindow(of: appElement) else {
            return .null
        }

        var matches: [(handle: Int64, frame: CGRect)] = []
        collectByRole(window, role: role, into: &matches)

        // Reading order: top-to-bottom, left-to-right. Elements at the same
        // y (within a small epsilon) sort by x. Without this, split layouts
        // can return matches in creation order which is meaningless to a
        // user looking at the screen.
        matches.sort { lhs, rhs in
            let dy = lhs.frame.minY - rhs.frame.minY
            if abs(dy) > 4 { return dy < 0 }
            return lhs.frame.minX < rhs.frame.minX
        }

        return makeFrameList(matches, symbols: self.context.symbols)
    }

    private func axClickHandleFunction(_ handleExpr: Expr) throws -> Expr {
        let handle = try handleExpr.asInt64()
        guard let element = elementsByHandle[handle] else {
            NSLog("AccessibilityLibrary: ax-click-handle: stale handle %lld", handle)
            return .void
        }

        guard let frame = axFrame(element) else { return .void }
        let center = CGPoint(x: frame.midX, y: frame.midY)

        // Activate the owning app first — clicks always go to whichever app
        // is frontmost at click-time, regardless of where the cursor is.
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if pid > 0 {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }

        // CGEvent screen coords match AX screen coords (top-left origin on
        // the primary display), so the saved cursor position round-trips
        // without conversion.
        let savedAX = currentMouseAXPos()

        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                           mouseCursorPosition: center, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                         mouseCursorPosition: center, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // Brief pause so the target app's mouseDown handler runs before we
        // warp the cursor back. Without this, the warp can race the click
        // delivery and cancel drag-detection logic mid-flight.
        usleep(15_000)
        CGWarpMouseCursorPosition(savedAX)
        return .void
    }

    /// Current mouse position in AX coordinates (top-left origin of primary).
    private func currentMouseAXPos() -> CGPoint {
        let cocoa = NSEvent.mouseLocation
        let primary = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: cocoa.x, y: primary - cocoa.y)
    }

    // MARK: - AX helpers

    private func runningApp(forBundleId bundleId: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    private func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let v = value else {
            // Fall back to the main window if no focused window — happens
            // when the app is in the background but its windows are visible.
            var mainValue: AnyObject?
            let mainResult = AXUIElementCopyAttributeValue(
                appElement, kAXMainWindowAttribute as CFString, &mainValue)
            if mainResult == .success, let mv = mainValue {
                return (mv as! AXUIElement)
            }
            return nil
        }
        return (v as! AXUIElement)
    }

    /// Walk the AX subtree rooted at `element`, appending every descendant
    /// whose AXRole equals `role` (along with its frame and a fresh handle)
    /// to `acc`. Containers like AXGroup / AXSplitGroup are descended into;
    /// AXSplitter, AXButton, AXStaticText etc. are leaves we don't recurse.
    /// Matched elements are NOT descended into — assumption is the caller
    /// queried for the visible/clickable level.
    private func collectByRole(_ element: AXUIElement,
                                role: String,
                                into acc: inout [(handle: Int64, frame: CGRect)]) {
        let myRole = axString(element, kAXRoleAttribute)
        if myRole == role, let frame = axFrame(element) {
            let handle = nextHandle
            nextHandle += 1
            elementsByHandle[handle] = element
            acc.append((handle, frame))
            return
        }
        guard let children = axChildren(element) else { return }
        for child in children {
            collectByRole(child, role: role, into: &acc)
        }
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value as? String : nil
    }

    private func axChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &value)
        return result == .success ? value as? [AXUIElement] : nil
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
                element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(
                element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard let posV = posValue, let szV = sizeValue else { return nil }
        AXValueGetValue(posV as! AXValue, .cgPoint, &point)
        AXValueGetValue(szV as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    // MARK: - Result building

    private func makeFrameList(_ matches: [(handle: Int64, frame: CGRect)],
                                symbols: SymbolTable) -> Expr {
        var result: Expr = .null
        for entry in matches.reversed() {
            let alist = SchemeAlistLookup.makeAlist([
                ("handle", .fixnum(entry.handle)),
                ("x", .fixnum(Int64(entry.frame.origin.x))),
                ("y", .fixnum(Int64(entry.frame.origin.y))),
                ("w", .fixnum(Int64(entry.frame.size.width))),
                ("h", .fixnum(Int64(entry.frame.size.height))),
            ], symbols: symbols)
            result = .pair(alist, result)
        }
        return result
    }
}
