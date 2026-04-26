import Nuke
import SwiftUI
import UIKit

struct Lightbox: View {
    let localData: Data?
    let remoteURL: URL?
    let onClose: () -> Void

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let loadedImage {
                ZoomableImageView(image: loadedImage)
                    .ignoresSafeArea()
            } else if remoteURL != nil {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.white)
                    .font(.largeTitle)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.4), in: Circle())
                    }
                    .accessibilityLabel("关闭")
                    .accessibilityIdentifier("lightboxClose")
                    .padding()
                }
                Spacer()
            }
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        if let localData, let image = UIImage(data: localData) {
            loadedImage = image
            return
        }

        guard let remoteURL else { return }

        do {
            loadedImage = try await ImagePipeline.shared.image(for: ImageRequest(url: remoteURL))
        } catch {
            // 保持空图标占位；用户可以直接关闭预览。
        }
    }
}
