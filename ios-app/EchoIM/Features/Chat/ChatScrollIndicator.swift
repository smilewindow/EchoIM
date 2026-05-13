import SwiftUI

// MARK: - Preference Keys

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Metrics

struct ScrollIndicatorMetrics {
    let indicatorHeight: CGFloat
    let indicatorTop: CGFloat
    let shouldShow: Bool

    private static let minHeight: CGFloat = 30

    init(contentHeight: CGFloat, viewportHeight: CGFloat, offset: CGFloat) {
        guard contentHeight > viewportHeight else {
            shouldShow = false
            indicatorHeight = 0
            indicatorTop = 0
            return
        }

        shouldShow = true
        indicatorHeight = max(
            viewportHeight / contentHeight * viewportHeight,
            Self.minHeight
        )

        let maxOffset = contentHeight - viewportHeight
        let normalized = maxOffset > 0
            ? min(max(offset / maxOffset, 0), 1)
            : 0
        indicatorTop = (1 - normalized) * (viewportHeight - indicatorHeight)
    }
}

// MARK: - View

struct ChatScrollIndicator: View {
    let metrics: ScrollIndicatorMetrics
    let isVisible: Bool

    private let indicatorWidth: CGFloat = 3

    var body: some View {
        RoundedRectangle(cornerRadius: indicatorWidth / 2)
            .fill(Color.primary.opacity(0.3))
            .frame(width: indicatorWidth, height: metrics.indicatorHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .offset(y: metrics.indicatorTop)
            .padding(.trailing, 2)
            .opacity(metrics.shouldShow && isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: isVisible)
    }
}
