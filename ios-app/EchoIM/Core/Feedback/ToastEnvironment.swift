import SwiftUI

private struct ShowErrorToastKey: EnvironmentKey {
    static let defaultValue: @MainActor (Error) -> Void = { _ in }
}

private struct ShowToastKey: EnvironmentKey {
    static let defaultValue: @MainActor (String) -> Void = { _ in }
}

extension EnvironmentValues {
    var showErrorToast: @MainActor (Error) -> Void {
        get { self[ShowErrorToastKey.self] }
        set { self[ShowErrorToastKey.self] = newValue }
    }

    var showToast: @MainActor (String) -> Void {
        get { self[ShowToastKey.self] }
        set { self[ShowToastKey.self] = newValue }
    }
}
