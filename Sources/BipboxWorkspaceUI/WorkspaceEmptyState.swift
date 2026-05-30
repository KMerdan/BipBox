import SwiftUI

struct WorkspaceEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: 340)
    }
}
