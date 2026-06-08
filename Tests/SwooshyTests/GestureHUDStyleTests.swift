import Testing
@testable import Swooshy

struct GestureHUDStyleTests {
    @Test
    func storageValuesRemainStable() {
        #expect(GestureHUDStyle.classic.storageValue == "classic")
        #expect(GestureHUDStyle.elegant.storageValue == "elegant")
        #expect(GestureHUDStyle.minimal.storageValue == "minimal_v2")
    }

    @Test
    func storageValuesDecodeCurrentAndLegacyNames() {
        let cases: [(storageValue: String?, style: GestureHUDStyle)] = [
            ("classic", .classic),
            ("elegant", .elegant),
            ("minimal", .elegant),
            ("minimal_v2", .minimal),
            ("swishLike", .minimal),
            ("unknown", .elegant),
            (nil, .elegant),
        ]

        for (storageValue, style) in cases {
            #expect(GestureHUDStyle(storageValue: storageValue) == style)
        }
    }
}
