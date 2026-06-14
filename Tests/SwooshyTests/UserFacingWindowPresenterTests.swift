import AppKit
import Testing
@testable import Swooshy

@MainActor
struct UserFacingWindowPresenterTests {
    @Test
    func presenterUsesRegularActivationPolicyBeforeShowingWindow() {
        var policies: [NSApplication.ActivationPolicy] = []
        let coordinator = UserFacingWindowActivationCoordinator<String>(
            setActivationPolicy: { policy in
                policies.append(policy)
                return true
            }
        )

        coordinator.presentWindow(id: "settings")

        #expect(policies == [.regular])
    }

    @Test
    func presenterReturnsToAccessoryAfterLastWindowCloses() {
        var policies: [NSApplication.ActivationPolicy] = []
        let coordinator = UserFacingWindowActivationCoordinator<String>(
            setActivationPolicy: { policy in
                policies.append(policy)
                return true
            }
        )

        coordinator.presentWindow(id: "settings")
        coordinator.presentWindow(id: "welcome")
        coordinator.closeWindow(id: "settings")
        coordinator.closeWindow(id: "welcome")

        #expect(policies == [.regular, .regular, .accessory])
    }

    @Test
    func repeatedPresentationDoesNotRequireMultipleCloses() {
        var policies: [NSApplication.ActivationPolicy] = []
        let coordinator = UserFacingWindowActivationCoordinator<String>(
            setActivationPolicy: { policy in
                policies.append(policy)
                return true
            }
        )

        coordinator.presentWindow(id: "settings")
        coordinator.presentWindow(id: "settings")
        coordinator.closeWindow(id: "settings")

        #expect(policies == [.regular, .regular, .accessory])
    }

    @Test
    func closingUnknownWindowLeavesActivationPolicyAlone() {
        var policies: [NSApplication.ActivationPolicy] = []
        let coordinator = UserFacingWindowActivationCoordinator<String>(
            setActivationPolicy: { policy in
                policies.append(policy)
                return true
            }
        )

        coordinator.closeWindow(id: "settings")

        #expect(policies.isEmpty)
    }
}
