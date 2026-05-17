import SwiftUI

struct LaunchSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTitle = false

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            ZStack {
                Image("LaunchSymbol")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

                Text("EchoIM")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: 82)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("EchoIM")
        .accessibilityIdentifier("launchSplash")
        .task {
            guard !showTitle else { return }

            try? await Task.sleep(nanoseconds: 150_000_000)

            let animation: Animation = reduceMotion ? .linear(duration: 0.12) : .easeOut(duration: 0.28)
            withAnimation(animation) {
                showTitle = true
            }
        }
    }
}
