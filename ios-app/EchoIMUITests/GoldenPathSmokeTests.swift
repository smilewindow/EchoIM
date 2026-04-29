import XCTest

/// P8 golden path：登录 → 会话列表 → 进入聊天 → 发文字 → 打开图片 picker。
final class GoldenPathSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGoldenPath_LoginSendTextAndOpenImagePicker() throws {
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

        let message = "p8-smoke-\(Int(Date().timeIntervalSince1970))"
        input.typeText(message)
        app.buttons["chatSend"].tap()

        // 只匹配本次发送的文字，避免被历史 bubble 误判。
        let textBubblePredicate = NSPredicate(
            format: "identifier BEGINSWITH 'chatBubble_text_' AND label CONTAINS[c] %@",
            message
        )
        let textBubble = app.descendants(matching: .any).matching(textBubblePredicate).firstMatch
        XCTAssertTrue(
            textBubble.waitForExistence(timeout: 10),
            "Expected chatBubble_text_* to show the message just sent"
        )

        let picker = app.buttons["chatImagePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        // PhotosPicker 是系统 UI；本 P8 smoke 只覆盖入口可打开，并回到聊天页。
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground)
        app.swipeDown(velocity: .fast)

        XCTAssertTrue(input.waitForExistence(timeout: 5))
    }
}
