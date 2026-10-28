import SwiftUI

struct PlayerFeedbackView: View {
    let message: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(message)
        }
        .font(.facts.weight(.semibold))
        .foregroundStyle(.textPrimary)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .videoOverlayGlass()
        .accessibilityElement(children: .combine)
    }
}
