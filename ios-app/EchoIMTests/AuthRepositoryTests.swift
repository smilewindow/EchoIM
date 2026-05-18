import Foundation
import Testing
@testable import EchoIM

@Suite("AuthRepository error mapping")
struct AuthRepositoryErrorMapTests {
    func makeBody(code: String, message: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "error": [
                "code": code,
                "message": message,
            ],
        ])
    }

    @Test
    func invalidInviteCodeIs403() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(status: 403, body: makeBody(code: "invalid_invite_code", message: "Invalid invite code"))
        )
        #expect(error == .invalidInviteCode)
    }

    @Test
    func invalidInviteCodeUsesServerCodeWhenMessageIsGeneric() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(status: 403, body: makeBody(code: "invalid_invite_code", message: "Forbidden"))
        )
        #expect(error == .invalidInviteCode)
    }

    @Test
    func emailTakenIs409() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(status: 409, body: makeBody(code: "email_already_in_use", message: "Email already in use"))
        )
        #expect(error == .emailTaken)
    }

    @Test
    func emailTakenUsesServerCodeWhenMessageIsGeneric() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(status: 409, body: makeBody(code: "email_already_in_use", message: "Conflict"))
        )
        #expect(error == .emailTaken)
    }

    @Test
    func usernameTakenIs409() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(status: 409, body: makeBody(code: "username_already_taken", message: "Username already taken"))
        )
        #expect(error == .usernameTaken)
    }

    @Test
    func fieldValidationEmailIs400() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(status: 400, body: makeBody(code: "invalid_email", message: "Invalid email address"))
        )

        if case .fieldValidation(let field, let message) = error {
            #expect(field == .email)
            #expect(message == "Invalid email address")
        } else {
            Issue.record("expected .fieldValidation(email), got \(error)")
        }
    }

    @Test
    func fieldValidationUsernameIs400() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(
                status: 400,
                body: makeBody(
                    code: "username_too_short",
                    message: "Username must be at least 3 characters"
                )
            )
        )

        if case .fieldValidation(let field, _) = error {
            #expect(field == .username)
        } else {
            Issue.record("expected .fieldValidation(username), got \(error)")
        }
    }

    @Test
    func fieldValidationPasswordIs400() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(
                status: 400,
                body: makeBody(
                    code: "invalid_request",
                    message: "body/password must NOT have fewer than 8 characters"
                )
            )
        )

        if case .fieldValidation(let field, _) = error {
            #expect(field == .password)
        } else {
            Issue.record("expected .fieldValidation(password)")
        }
    }

    @Test
    func fieldValidationInviteCodeIs400() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(
                status: 400,
                body: makeBody(
                    code: "invalid_request",
                    message: "body/inviteCode must NOT have fewer than 1 character"
                )
            )
        )

        if case .fieldValidation(let field, _) = error {
            #expect(field == .inviteCode)
        } else {
            Issue.record("expected .fieldValidation(inviteCode)")
        }
    }

    @Test
    func fieldValidationUnknownFieldFallsToToast() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(status: 400, body: makeBody(code: "invalid_request", message: "something obscure"))
        )

        if case .fieldValidation(let field, _) = error {
            #expect(field == nil)
        } else {
            Issue.record("expected .fieldValidation(nil)")
        }
    }

    @Test
    func loginInvalidCredentialsIs401() {
        let error = AuthRepositoryImpl.mapLoginError(.unauthorized)
        #expect(error == .invalidCredentials)
    }
}
