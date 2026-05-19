import Foundation
import Observation

@MainActor
@Observable
final class ToastCenter {
    private(set) var current: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String) {
        dismissTask?.cancel()
        if current?.message != message {
            current = ToastMessage(message: message)
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                current = nil
            }
        }
    }

    func show(error: Error) {
        guard let message = ErrorPresenter.displayMessage(for: error) else {
            return
        }

        show(message)
    }

    func clear() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let message: String
}
