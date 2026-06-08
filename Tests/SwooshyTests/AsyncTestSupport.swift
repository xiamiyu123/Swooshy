@MainActor
func yieldForPendingMainActorWork() async {
    for _ in 0 ..< 3 {
        await Task.yield()
    }
}
