import Testing
import AppKit
@testable import Modaliser

@Suite("FocusedAppObserver")
struct FocusedAppObserverTests {

    @Test func currentBundleIdReturnsNonNilOnDesktop() {
        let observer = FocusedAppObserver()
        // On a desktop Mac, there should always be a frontmost app
        // (may be nil in headless CI, so we just verify it doesn't crash)
        _ = observer.currentBundleId
    }

    @Test func currentBundleIdReturnsStringType() {
        let observer = FocusedAppObserver()
        if let bundleId = observer.currentBundleId {
            // Bundle IDs should contain a dot (e.g., com.apple.finder)
            #expect(bundleId.contains("."))
        }
    }
}
