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
        let a = ImageSendStage.uploaded(mediaURL: "/uploads/messages/1-1.jpg")
        let b = ImageSendStage.uploaded(mediaURL: "/uploads/messages/1-1.jpg")
        let c = ImageSendStage.uploaded(mediaURL: "/uploads/messages/1-2.jpg")
        #expect(a == b)
        #expect(a != c)
        #expect(a != .notStarted)
    }

    @Test
    func uploadedExtractsMediaURL() {
        let stage = ImageSendStage.uploaded(mediaURL: "/uploads/messages/1-1.jpg")
        if case .uploaded(let url) = stage {
            #expect(url == "/uploads/messages/1-1.jpg")
        } else {
            Issue.record("expected uploaded case")
        }
    }
}
