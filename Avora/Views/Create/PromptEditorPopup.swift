import SwiftUI

// Sheet for composing the custom-style prompt. Edits a private draft so dismissing
// or tapping Cancel leaves the original prompt untouched; only Done commits back.
struct PromptEditorPopup: View {
    let initialText: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(initialText: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.initialText = initialText
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: initialText)
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { !trimmed.isEmpty && trimmed.count <= 2000 }

    var body: some View {
        NavigationStack {
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                TextField("Describe your style…", text: $draft, axis: .vertical)
                    .lineLimit(4...40)
                    .font(.avoraBody)
                    .foregroundStyle(Color.avoraTextPrimary)
                    .focused($focused)
                    .padding(Spacing.md)
                    .avoraGlass(in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                Text("\(trimmed.count)/2000")
                    .font(.avoraCaption2)
                    .foregroundStyle(trimmed.count > 2000 ? Color.avoraError : Color.avoraTextTertiary)
                    .padding(.trailing, Spacing.xs)

                Spacer()
            }
            .padding(Spacing.lg)
            .navigationTitle("Describe your style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(draft) }
                        .disabled(!valid)
                }
            }
        }
        .presentationDetents([.large])
        .task { focused = true }
    }
}
