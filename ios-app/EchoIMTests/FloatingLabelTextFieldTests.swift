import Testing
import SwiftUI
@testable import EchoIM

@Suite("FloatingLabelTextField")
struct FloatingLabelTextFieldTests {
    @Test
    func accessibilityIdExistsWhenEmpty() {
        var text = ""
        let field = FloatingLabelTextField(
            label: "用户名",
            text: Binding(get: { text }, set: { text = $0 }),
            autocapitalization: .never,
            accessibilityId: "smokeField"
        )
        #expect(field.accessibilityId == "smokeField")
    }
}
