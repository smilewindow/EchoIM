import XCTest

final class ClearCacheSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testClearCacheFromMeTabDoesNotCrash() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset-keychain"]
        app.launch()

        let email = app.textFields["loginEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("smoke@test.local")

        let password = app.secureTextFields["loginPassword"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("password123")

        app.buttons["loginSubmit"].tap()

        let tabView = app.otherElements["mainTabView"]
        XCTAssertTrue(tabView.waitForExistence(timeout: 10))

        let meTab = app.tabBars.buttons["我"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 10))
        meTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let username = app.staticTexts["homeUsername"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))

        let clearButton = app.descendants(matching: .any)["meClearCache"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        clearButton.tap()

        let confirm = app.buttons["清除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        let chatsTab = app.tabBars.buttons["聊天"]
        chatsTab.tap()

        let conversationList = app.descendants(matching: .any)["conversationsList"]
        XCTAssertTrue(conversationList.waitForExistence(timeout: 10))
    }
}
