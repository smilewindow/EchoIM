import XCTest

final class UserDetailFromChatSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTapPrincipalAvatarPushesUserDetail() throws {
        let app = launchAndEnterFirstConversation()

        // 顶部头像 + principalTitle 必须在场
        let avatar = app.descendants(matching: .any)["chatPeerAvatar"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 5), "ChatView 顶部应显示对方头像")

        let principal = app.descendants(matching: .any)["chatPrincipalTitle"]
        XCTAssertTrue(principal.exists)

        // 点击 principal 区跳到 UserDetailView
        principal.tap()

        let detailRoot = app.descendants(matching: .any)["userDetailRoot"]
        XCTAssertTrue(detailRoot.waitForExistence(timeout: 5), "应 push 进入 UserDetailView")

        let detailAvatar = app.descendants(matching: .any)["userDetailAvatar"]
        XCTAssertTrue(detailAvatar.exists)

        let detailTitle = app.descendants(matching: .any)["userDetailDisplayTitle"]
        XCTAssertTrue(detailTitle.exists)
    }

    // MARK: - Helpers

    /// 复制 PresenceTypingSmokeTests 的登入 + 选第一行会话路径。
    @MainActor
    private func launchAndEnterFirstConversation() -> XCUIApplication {
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

        let list = app.descendants(matching: .any)["conversationsList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))

        let firstRow = list.descendants(matching: .cell).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        return app
    }
}
