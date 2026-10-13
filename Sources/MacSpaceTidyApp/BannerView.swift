import SwiftUI

struct BannerView<Accessory: View>: View {
    let systemImage: String
    let tint: Color
    let text: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
            Spacer()
            accessory()
        }
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension BannerView where Accessory == EmptyView {
    init(systemImage: String, tint: Color, text: String) {
        self.init(systemImage: systemImage, tint: tint, text: text) { EmptyView() }
    }
}
