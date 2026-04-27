import XCTest

final class PresenceTypingSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testChatHeaderShowsPrincipalTitleIdentifier() throws {
        let app = launchAndEnterFirstConversation()

        // Task 9 把 .navigationTitle 改成 .toolbar(.principal) 后，
        // 顶部应当能查到自定义的 chatPrincipalTitle 元素。
        let principal = app.descendants(matching: .any)["chatPrincipalTitle"]
        XCTAssertTrue(
            principal.waitForExistence(timeout: 5),
            "ChatView principal title 自定义视图应存在"
        )

        // 进入瞬间没有"对方正在输入"——除非 fixture 数据里对方真的在打字。
        XCTAssertFalse(
            app.staticTexts["chatPeerTyping"].exists,
            "刚进入会话不应显示 chatPeerTyping"
        )
    }

    @MainActor
    func testOwnInputDoesNotRenderPeerTyping() throws {
        let app = launchAndEnterFirstConversation()

        let input = app.descendants(matching: .any)["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("hi")

        // 本端打字不应在自己屏幕上渲染 chatPeerTyping
        // （这是 vm.peerIsTyping 通过 typingStore 读对方状态的契约）
        XCTAssertFalse(
            app.staticTexts["chatPeerTyping"].exists,
            "本端打字不应触发 chatPeerTyping 渲染"
        )
    }

    // MARK: - Helpers

    /// 复制 ChatSmokeTests 的登入 → 选第一行会话路径。fixture 账号需提前在测试服务端建好。
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
