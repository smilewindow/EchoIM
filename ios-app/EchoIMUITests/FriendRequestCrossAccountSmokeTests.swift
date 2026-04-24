import XCTest

final class FriendRequestCrossAccountSmokeTests: XCTestCase {
    private let app = XCUIApplication()
    private let password = "password123"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    @MainActor
    func testCrossAccountFriendRequestFlow() async throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8)
        let sender = TestUser(
            username: "uismokea\(suffix)",
            email: "uismokea\(suffix)@test.local",
            password: password
        )
        let receiver = TestUser(
            username: "uismokeb\(suffix)",
            email: "uismokeb\(suffix)@test.local",
            password: password
        )

        try await register(sender)
        try await register(receiver)

        launchFresh()
        try login(email: sender.email, password: sender.password)
        try openContacts()
        try sendFriendRequest(toUsername: receiver.username)

        try openFriendRequests()
        try require(
            element("sentFriendRequest_\(receiver.username)"),
            timeout: 10,
            "\(sender.username) 发出的 \(receiver.username) 好友申请应出现在已发送列表"
        )

        launchFresh()
        try login(email: receiver.email, password: receiver.password)
        try openContacts()
        try acceptIncomingFriendRequest(fromUsername: sender.username)

        try require(
            element("friendRow_\(sender.username)"),
            timeout: 10,
            "同意申请后，\(sender.username) 应出现在 \(receiver.username) 的好友列表"
        )

        launchFresh()
        try login(email: sender.email, password: sender.password)
        try openContacts()

        try require(
            element("friendRow_\(receiver.username)"),
            timeout: 10,
            "好友申请被接受后，\(receiver.username) 应出现在 \(sender.username) 的好友列表"
        )

        try openFriendRequests()
        try require(
            element("historyFriendRequest_sent_\(receiver.username)_accepted"),
            timeout: 10,
            "\(sender.username) 的历史记录应显示发送给 \(receiver.username) 的申请已接受"
        )
    }

    private func launchFresh() {
        app.terminate()
        app.launchArguments = ["-uitest-reset-keychain"]
        app.launch()
    }

    private func login(email: String, password: String) throws {
        let emailField = try require(app.textFields["loginEmail"], timeout: 8, "登录邮箱输入框应出现")
        emailField.tap()
        emailField.typeText(email)

        let passwordField = try require(
            app.secureTextFields["loginPassword"],
            timeout: 5,
            "登录密码输入框应出现"
        )
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["loginSubmit"].tap()
        try require(app.otherElements["mainTabView"], timeout: 12, "登录后应进入 MainTabView")
    }

    private func openContacts() throws {
        let contactsTab = try require(app.tabBars.buttons["联系人"], timeout: 5, "联系人 tab 应出现")
        contactsTab.tap()

        try require(app.buttons["openUserSearch"], timeout: 10, "联系人页的添加好友按钮应出现")
    }

    private func sendFriendRequest(toUsername username: String) throws {
        try require(app.buttons["openUserSearch"], timeout: 5, "添加好友按钮应出现").tap()

        let query = try require(app.textFields["userSearchQuery"], timeout: 5, "用户搜索输入框应出现")
        query.tap()
        query.typeText(username)

        try require(
            element("userSearchResult_\(username)"),
            timeout: 10,
            "搜索结果应包含 \(username)"
        )

        // 新注册的接收方按精确用户名搜索，只会出现目标结果；按钮文案比子按钮 id 更稳定。
        let sendButton = try require(app.buttons["添加"].firstMatch, timeout: 5, "添加按钮应出现")
        sendButton.tap()

        try closeSheet()
    }

    private func acceptIncomingFriendRequest(fromUsername username: String) throws {
        try openFriendRequests()

        let incomingRow = element("incomingFriendRequest_\(username)")
        if !incomingRow.waitForExistence(timeout: 10) {
            app.swipeDown()
        }
        try require(
            incomingRow,
            timeout: 10,
            "应能看到 \(username) 发来的待处理好友申请"
        )

        // 接收方是本测试创建的新账号，待处理申请只有这一条。
        let acceptButton = try require(app.buttons["同意"].firstMatch, timeout: 5, "同意按钮应出现")
        acceptButton.tap()

        try require(
            element("historyFriendRequest_received_\(username)_accepted"),
            timeout: 10,
            "同意后，历史记录应显示收到的 \(username) 申请已接受"
        )

        try closeSheet()
    }

    private func openFriendRequests() throws {
        let requestButton = try require(
            app.buttons["openFriendRequests"],
            timeout: 5,
            "好友申请入口应出现"
        )
        requestButton.tap()
        try require(app.navigationBars["好友申请"], timeout: 5, "好友申请 sheet 应打开")
    }

    private func closeSheet() throws {
        let closeButton = try require(app.buttons["关闭"], timeout: 5, "关闭按钮应出现")
        closeButton.tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        timeout: TimeInterval,
        _ message: String
    ) throws -> XCUIElement {
        guard element.waitForExistence(timeout: timeout) else {
            throw BootstrapError(message: message)
        }
        return element
    }

    private func register(_ user: TestUser) async throws {
        var request = URLRequest(url: registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RegisterRequest(
                username: user.username,
                email: user.email,
                password: user.password,
                inviteCode: inviteCode
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BootstrapError(message: "注册 \(user.email) 失败：没有收到 HTTP 响应")
        }
        guard httpResponse.statusCode == 201 else {
            let body = String(data: data, encoding: .utf8) ?? "<empty body>"
            throw BootstrapError(
                message: "注册 \(user.email) 失败：HTTP \(httpResponse.statusCode) \(body)。"
                    + "若返回 403，请设置 ECHOIM_UITEST_INVITE_CODE 匹配后端 INVITE_CODES。"
            )
        }
    }

    private var registerURL: URL {
        guard var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false) else {
            preconditionFailure("invalid API base URL: \(apiBaseURL)")
        }
        components.path = "/api/auth/register"
        guard let url = components.url else {
            preconditionFailure("invalid register URL from base URL: \(apiBaseURL)")
        }
        return url
    }

    private var apiBaseURL: URL {
        let rawValue = ProcessInfo.processInfo.environment["ECHOIM_UITEST_BASE_URL"]
            ?? "http://localhost:3000"
        guard let url = URL(string: rawValue) else {
            preconditionFailure("invalid ECHOIM_UITEST_BASE_URL: \(rawValue)")
        }
        return url
    }

    private var inviteCode: String {
        ProcessInfo.processInfo.environment["ECHOIM_UITEST_INVITE_CODE"] ?? "letschat"
    }
}

private struct TestUser {
    let username: String
    let email: String
    let password: String
}

private struct RegisterRequest: Encodable {
    let username: String
    let email: String
    let password: String
    let inviteCode: String
}

private struct BootstrapError: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}
