import XCTest

final class LoginSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        let app = XCUIApplication()
        // 复用测试专用启动参数，让 smoke 跑完后把模拟器恢复回未登录态，
        // 避免后续手工验证被残留 Keychain 污染。
        app.launchArguments += ["-uitest-reset-keychain"]
        app.launch()
        app.terminate()
    }

    @MainActor
    func testLoginHappyPath() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-keychain"]
        app.launch()

        let email = app.textFields["loginEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("smoke@test.local")

        let password = app.secureTextFields["loginPassword"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("password123")

        app.buttons["loginSubmit"].tap()

        let username = app.staticTexts["homeUsername"]
        XCTAssertTrue(username.waitForExistence(timeout: 10))
    }
}
