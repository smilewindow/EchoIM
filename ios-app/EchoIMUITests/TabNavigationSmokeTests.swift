import XCTest

final class TabNavigationSmokeTests: XCTestCase {
    @MainActor
    func testLandsOnMainTabAndNavigatesToContacts() throws {
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

        let contactsTab = app.tabBars.buttons["联系人"]
        XCTAssertTrue(contactsTab.waitForExistence(timeout: 3))
        contactsTab.tap()

        let searchButton = app.buttons["openUserSearch"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))

        let friendsList = app.descendants(matching: .any)["friendsList"]
        let friendsEmpty = app.descendants(matching: .any)["friendsEmpty"]
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if friendsList.exists || friendsEmpty.exists {
                return
            }
            usleep(200_000)
        }

        XCTFail("Expected friendsList or friendsEmpty to appear")
    }
}
