import Testing
import CoreGraphics
@testable import DisplayCore

struct DisplayTargetTests {
    let builtInScreen = ScreenInfo(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        isBuiltIn: true
    )

    let externalScreen = ScreenInfo(
        id: 2,
        frame: CGRect(x: 1512, y: 0, width: 1920, height: 1200),
        isBuiltIn: false
    )

    @Test func mouseInBuiltInScreen() {
        let screens = [builtInScreen, externalScreen]
        let target = resolveTarget(mouse: CGPoint(x: 100, y: 100), screens: screens)
        #expect(target == .builtIn)
    }

    @Test func mouseInExternalScreen() {
        let screens = [builtInScreen, externalScreen]
        let target = resolveTarget(mouse: CGPoint(x: 2000, y: 500), screens: screens)
        #expect(target == .external(2))
    }

    @Test func mouseOutsideAllScreens() {
        let screens = [builtInScreen, externalScreen]
        let target = resolveTarget(mouse: CGPoint(x: -5, y: -5), screens: screens)
        #expect(target == .none)
    }

    @Test func emptyScreensList() {
        let target = resolveTarget(mouse: CGPoint(x: 100, y: 100), screens: [])
        #expect(target == .none)
    }

    @Test func mouseOnSharedEdge() {
        let screens = [builtInScreen, externalScreen]
        // Shared vertical boundary at x = 1512 belongs to external screen (right side)
        let target = resolveTarget(mouse: CGPoint(x: 1512, y: 500), screens: screens)
        #expect(target == .external(2))
    }
}
