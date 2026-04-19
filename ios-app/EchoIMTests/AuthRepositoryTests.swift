import Foundation
import Testing
@testable import EchoIM

@Suite("AuthRepository error mapping")
struct AuthRepositoryErrorMapTests {
    func makeBody(_ message: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["error": message])
    }

    @Test
    func invalidInviteCodeIs403() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(status: 403, body: makeBody("Invalid invite code"))
        )
        #expect(error == .invalidInviteCode)
    }

    @Test
    func emailTakenIs409() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(status: 409, body: makeBody("Email already in use"))
        )
        #expect(error == .emailTaken)
    }

    @Test
    func usernameTakenIs409() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(status: 409, body: makeBody("Username already taken"))
        )
        #expect(error == .usernameTaken)
    }

    @Test
    func fieldValidationEmailIs400() {
        let error = AuthRepositoryImpl.mapRegisterError(
            .http(status: 400, body: makeBody("Invalid email address"))
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
            .http(status: 400, body: makeBody("Username must be at least 3 characters"))
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
            .http(status: 400, body: makeBody("body/password must NOT have fewer than 8 characters"))
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
            .http(status: 400, body: makeBody("body/inviteCode must NOT have fewer than 1 character"))
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
            .http(status: 400, body: makeBody("something obscure"))
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
