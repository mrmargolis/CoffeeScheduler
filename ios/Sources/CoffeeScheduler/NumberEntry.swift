import SwiftUI
import UIKit

extension View {
    /// A field for a number: its keypad, right-aligned, and wide enough to
    /// hit. A tap selects the whole amount (see `selectsNumbersOnTap`).
    func numberEntry(_ keyboard: UIKeyboardType = .decimalPad) -> some View {
        keyboardType(keyboard)
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 90)
    }

    /// Select the whole amount when a number field is tapped, so typing
    /// replaces it: the fields are too narrow to tap past the end of a
    /// number, and the cursor lands in front of it.
    func selectsNumbersOnTap() -> some View {
        onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            guard let field = note.object as? UITextField,
                [.numberPad, .decimalPad].contains(field.keyboardType)
            else { return }
            Task { @MainActor in field.selectAll(nil) }
        }
    }
}
