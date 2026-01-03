import SwiftUI

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct SummaryRow: View {
    let title: String
    let value: String
    var emphasis: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(emphasis ? .primary : .secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .fontWeight(emphasis ? .semibold : .regular)
        }
    }
}
