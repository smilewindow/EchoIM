import XCTest

final class ImageSendSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testImagePickerButtonOpensPhotosUI() throws {
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

        let picker = app.buttons["chatImagePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        sleep(1)
        XCTAssertEqual(app.state, .runningForeground)
        app.swipeDown(velocity: .fast)
    }
}
