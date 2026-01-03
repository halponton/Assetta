import SwiftUI

struct GlassCard<Content: View>: View {
    let title: String?
    let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

func formatMinorCurrency(_ minor: Int64) -> String {
    let number = NSDecimalNumber(value: minor).dividing(by: 100)
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = Locale.current.currency?.identifier ?? "GBP"
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: number) ?? "\(number)"
}
