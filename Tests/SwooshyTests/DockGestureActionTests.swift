import Testing
@testable import Swooshy

struct DockGestureActionTests {
    @Test
    func dockGestureDefaultsMatchFallbackBindings() {
        #expect(DockGestureBindings.defaults.count == DockGestureKind.allCases.count)

        for binding in DockGestureBindings.defaults {
            #expect(DockGestureBindings.fallbackBinding(for: binding.gesture) == binding)
        }
    }

    @Test
    func titleBarGestureDefaultsMatchFallbackBindingsForSupportedGestures() {
        #expect(TitleBarGestureBindings.defaults.count == TitleBarGestureBindings.supportedGestures.count)

        for binding in TitleBarGestureBindings.defaults {
            #expect(TitleBarGestureBindings.fallbackBinding(for: binding.gesture) == binding)
        }
    }

    @Test
    func titleBarBindingReturnsNilForUnsupportedGestures() {
        let unsupportedGesture = DockGestureKind.allCases.first {
            TitleBarGestureBindings.supportedGestures.contains($0) == false
        }

        if let unsupportedGesture {
            #expect(TitleBarGestureBindings.binding(for: unsupportedGesture, in: []) == nil)
        } else {
            #expect(TitleBarGestureBindings.supportedGestures == DockGestureKind.allCases)
        }
    }
}
