import SwiftUI

/// A multi-line notes box: Return starts a new line, and a Done button above the keyboard closes it.
/// Used for notes on places, hotels, flights, expenses and in the share sheet.
struct NotesEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 80

    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
        }
        .toolbar {
            // Return adds a new line, so this is how the keyboard closes.
            ToolbarItemGroup(placement: .keyboard) {
                if focused {
                    Spacer()
                    Button("Done") { focused = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
