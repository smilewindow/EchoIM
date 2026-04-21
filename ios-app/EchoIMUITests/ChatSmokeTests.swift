import XCTest

final class ChatSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSendTextMessage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-keychain"]
        app.launch()

        // 登录 smoke 账号，测试环境需要预先准备一条会话。
        let email = app.textFields["loginEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("smoke@test.local")

        let password = app.secureTextFields["loginPassword"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("password123")

        app.buttons["loginSubmit"].tap()

        let tabView = app.otherElements["mainTabView"]
        XCTAssertTrue(tabView.waitForExistence(timeout: 10))

        let conversationsList = app.descendants(matching: .any)["conversationsList"]
        XCTAssertTrue(conversationsList.waitForExistence(timeout: 10))

        let firstRow = conversationsList.descendants(matching: .cell).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        let input = app.descendants(matching: .any)["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()

        let message = "smoke-\(Int(Date().timeIntervalSince1970))"
        input.typeText(message)
        app.buttons["chatSend"].tap()

        app.navigationBars.buttons.firstMatch.tap()

        let predicate = NSPredicate(format: "label CONTAINS[c] %@", message)
        let previewCell = conversationsList.staticTexts.containing(predicate).firstMatch
        XCTAssertTrue(
            previewCell.waitForExistence(timeout: 10),
            "expected conversation preview to show the message just sent"
        )
    }
}
