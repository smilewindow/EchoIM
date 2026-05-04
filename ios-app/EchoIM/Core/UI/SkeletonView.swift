import SwiftUI

// MARK: - Shimmer Modifier
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.white.opacity(0.5), location: 0.4),
                            .init(color: .clear, location: 0.8),
                        ],
                        startPoint: UnitPoint(x: phase, y: 0),
                        endPoint: UnitPoint(x: phase + 1, y: 0)
                    )
                    .frame(width: width * 2)
                    .offset(x: phase * width)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton 矩形工具
private struct SkeletonRect: View {
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(uiColor: .systemFill))
            .frame(width: width, height: height)
            .shimmer()
    }
}

// MARK: - ConversationRowSkeleton
struct ConversationRowSkeleton: View {
    let nameWidth: CGFloat
    let previewWidth: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(uiColor: .systemFill))
                .frame(width: 46, height: 46)
                .shimmer()

            VStack(alignment: .leading, spacing: 6) {
                SkeletonRect(width: nameWidth, height: 14)
                SkeletonRect(width: previewWidth, height: 12)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}

// MARK: - ConversationsListSkeleton
struct ConversationsListSkeleton: View {
    private let presets: [(CGFloat, CGFloat)] = [
        (88, 160), (72, 140), (96, 120), (80, 150), (68, 135)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(presets.indices, id: \.self) { i in
                ConversationRowSkeleton(nameWidth: presets[i].0, previewWidth: presets[i].1)
                Divider()
                    .padding(.leading, 70)
                    .foregroundStyle(Color.echoBlue.opacity(0.06))
            }
        }
    }
}

// MARK: - ChatSkeletonView
struct ChatSkeletonView: View {
    private let presets: [(isRight: Bool, widthRatio: CGFloat)] = [
        (false, 0.55), (true, 0.45), (false, 0.62),
        (true, 0.38), (false, 0.50), (true, 0.42)
    ]

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 10) {
                Spacer()
                ForEach(presets.indices, id: \.self) { i in
                    let preset = presets[i]
                    HStack {
                        if preset.isRight { Spacer() }
                        SkeletonRect(
                            width: geo.size.width * preset.widthRatio,
                            height: 34,
                            cornerRadius: 16
                        )
                        if !preset.isRight { Spacer() }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 12)
        }
    }
}
