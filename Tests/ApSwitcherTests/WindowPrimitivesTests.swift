import CoreGraphics
import Testing
@testable import ApSwitcher

struct WindowPrimitivesTests {
    @Test func windowFrameRoundsCoordinatesAndSize() {
        let frame = WindowFrame(CGRect(x: 10.6, y: 20.4, width: 300.5, height: 199.6))

        #expect(frame.x == 11)
        #expect(frame.y == 20)
        #expect(frame.width == 301)
        #expect(frame.height == 200)
    }

    @Test func windowIdentityEqualityIncludesOrdinalAndFrame() {
        let baseFrame = WindowFrame(CGRect(x: 0, y: 0, width: 100, height: 100))
        let first = WindowIdentity(appPID: 7, title: "Editor", frame: baseFrame, ordinal: 0)
        let second = WindowIdentity(appPID: 7, title: "Editor", frame: baseFrame, ordinal: 1)

        #expect(first != second)
    }
}
