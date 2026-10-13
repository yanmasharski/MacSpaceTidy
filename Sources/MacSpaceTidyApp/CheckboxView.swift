import SwiftUI

/// Checkbox with a mixed state for category headers.
struct CheckboxView: View {
    enum State {
        case off
        case on
        case mixed
    }

    let state: State
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: imageName)
                .font(.system(size: 15))
                .foregroundStyle(state == .off ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel(state == .on ? "Selected" : "Not selected")
    }

    private var imageName: String {
        switch state {
        case .off: return "square"
        case .on: return "checkmark.square.fill"
        case .mixed: return "minus.square.fill"
        }
    }
}
