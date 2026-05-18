import SwiftUI

private struct ShowErrorToastKey: EnvironmentKey {
    static let defaultValue: @MainActor (Error) -> Void = { _ in }
}

extension EnvironmentValues {
    var showErrorToast: @MainActor (Error) -> Void {
        get { self[ShowErrorToastKey.self] }
        set { self[ShowErrorToastKey.self] = newValue }
    }
}
