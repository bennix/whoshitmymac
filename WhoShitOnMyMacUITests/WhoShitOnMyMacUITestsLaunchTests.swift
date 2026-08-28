import XCTest

final class WhoShitOnMyMacUITestsLaunchTests: XCTestCase {
    func testLaunchTestDisabled() {
        // 第一期不跑 UI 启动套件，避免无签名环境下 runner 崩溃。
        XCTAssertTrue(true)
    }
}
