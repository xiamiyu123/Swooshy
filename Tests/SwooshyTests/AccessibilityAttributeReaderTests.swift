import ApplicationServices
import Testing
@testable import Swooshy

struct AccessibilityAttributeReaderTests {
    @Test
    func windowContainingInvalidElementReturnsNil() {
        // An AX element for a nonexistent process fails every attribute read,
        // mirroring the invalid window elements some WebView-shell apps return
        // from their AXWindow attribute. window(containing:) must not surface
        // such elements so callers can fall back to other window resolution.
        let invalidElement = AXUIElementCreateApplication(-1)

        #expect(AXAttributeReader.window(containing: invalidElement) == nil)
    }
}
