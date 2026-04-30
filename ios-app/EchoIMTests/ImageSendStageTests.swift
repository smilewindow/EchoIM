import Testing
@testable import EchoIM

@Suite
struct ImageSendStageTests {
    @Test
    func equalityIgnoresAssociatedValueOnNotStarted() {
        #expect(ImageSendStage.notStarted == .notStarted)
    }

    @Test
    func uploadedEqualityChecksMediaURL() {
        let a = ImageSendStage.uploaded(mediaURL: "/uploads/messages/1-1.jpg", mediaWidth: 1, mediaHeight: 1)
        let b = ImageSendStage.uploaded(mediaURL: "/uploads/messages/1-1.jpg", mediaWidth: 1, mediaHeight: 1)
        let c = ImageSendStage.uploaded(mediaURL: "/uploads/messages/1-2.jpg", mediaWidth: 1, mediaHeight: 1)
        #expect(a == b)
        #expect(a != c)
        #expect(a != .notStarted)
    }

    @Test
    func uploadedExtractsMediaURL() {
        let stage = ImageSendStage.uploaded(mediaURL: "/uploads/messages/1-1.jpg", mediaWidth: 1600, mediaHeight: 900)
        if case .uploaded(let url, let width, let height) = stage {
            #expect(url == "/uploads/messages/1-1.jpg")
            #expect(width == 1600)
            #expect(height == 900)
        } else {
            Issue.record("expected uploaded case")
        }
    }
}
