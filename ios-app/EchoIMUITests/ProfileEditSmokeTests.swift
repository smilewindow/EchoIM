import XCTest

final class ProfileEditSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTapEditProfileShowsForm() throws {
        let app = launchAndLogin()

        // 切到"我"tab
        let meTab = app.tabBars.buttons["我"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 5))
        meTab.tap()

        // 点"编辑资料"
        let entry = app.descendants(matching: .any)["meEditProfile"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Me 页应显示编辑资料入口")
        entry.tap()

        // displayName 输入框 + 保存按钮 + 头像 PhotosPicker 触发器都应该可见
        let displayNameField = app.descendants(matching: .any)["profileEditDisplayName"]
        XCTAssertTrue(displayNameField.waitForExistence(timeout: 5))

        let saveButton = app.descendants(matching: .any)["profileEditSaveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))

        let pickAvatar = app.descendants(matching: .any)["profileEditPickAvatar"]
        XCTAssertTrue(pickAvatar.waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    @MainActor
    private func launchAndLogin() -> XCUIApplication {
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
        return app
    }
}
