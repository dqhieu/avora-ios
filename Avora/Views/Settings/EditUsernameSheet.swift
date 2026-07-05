import SwiftUI

struct EditUsernameSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var status: Status = .idle
    @State private var checkTask: Task<Void, Never>?

    enum Status: Equatable {
        case idle, checking, available, taken, invalid, saving
    }

    init(current: String) {
        _text = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("username", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: text) { _, _ in scheduleCheck() }
                } footer: {
                    footerLabel
                }
            }
            .navigationTitle("Username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(status != .available)
                }
            }
        }
    }

    @ViewBuilder private var footerLabel: some View {
        switch status {
        case .idle:      Text("3–20 characters: lowercase letters, numbers, underscore.")
        case .checking:  Text("Checking availability…")
        case .available: Text("Available").foregroundStyle(.green)
        case .taken:     Text("That username is taken.").foregroundStyle(.red)
        case .invalid:   Text("Use 3–20 lowercase letters, numbers, or underscore (at least one letter).").foregroundStyle(.red)
        case .saving:    Text("Saving…")
        }
    }

    private func scheduleCheck() {
        checkTask?.cancel()
        let candidate = text
        if candidate == (app.profile?.username ?? "") {
            status = .idle
            return
        }
        guard UsernameValidator.isValid(candidate) else {
            status = .invalid
            return
        }
        status = .checking
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            let available = (try? await AvoraAPI.shared.isUsernameAvailable(candidate)) ?? false
            if Task.isCancelled || candidate != text { return }
            status = available ? .available : .taken
        }
    }

    private func save() {
        status = .saving
        Task {
            let result = await app.updateUsername(text)
            switch result {
            case .ok:      dismiss()
            case .taken:   status = .taken
            case .invalid: status = .invalid
            }
        }
    }
}
