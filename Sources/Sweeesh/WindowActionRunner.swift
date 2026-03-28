@MainActor
protocol WindowActionRunning {
    func run(_ action: WindowAction) throws
}

@MainActor
struct WindowActionRunner: WindowActionRunning {
    private let windowManager: WindowManaging
    private let layoutEngine: WindowLayoutEngine

    init(
        windowManager: WindowManaging,
        layoutEngine: WindowLayoutEngine
    ) {
        self.windowManager = windowManager
        self.layoutEngine = layoutEngine
    }

    func run(_ action: WindowAction) throws {
        try windowManager.perform(action, layoutEngine: layoutEngine)
    }
}
