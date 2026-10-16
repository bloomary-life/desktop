import Foundation
import Testing
@testable import Bloomary_Desktop

struct DraftPolicyTests {
    @Test
    func saveCreatesNewDraftAtTop() {
        let existing = Draft(body: "Existing")
        let now = Date(timeIntervalSince1970: 100)

        let result = DraftPolicy.save(drafts: [existing], editingDraftID: nil, body: "New post", maxDrafts: 5, now: now)

        #expect(result.drafts.count == 2)
        #expect(result.drafts.first?.body == "New post")
        #expect(result.drafts.first?.createdAt == now)
        #expect(result.editingDraftID == result.drafts.first?.id)
        #expect(result.changedDraft?.body == "New post")
        #expect(result.limitReached == false)
    }

    @Test
    func saveUpdatesEditedDraftInPlace() {
        let edited = Draft(id: UUID(), body: "Old", updatedAt: Date(timeIntervalSince1970: 10))
        let other = Draft(id: UUID(), body: "Other", updatedAt: Date(timeIntervalSince1970: 20))
        let now = Date(timeIntervalSince1970: 100)

        let result = DraftPolicy.save(drafts: [other, edited], editingDraftID: edited.id, body: "Updated", maxDrafts: 5, now: now)

        #expect(result.drafts.count == 2)
        #expect(result.editingDraftID == edited.id)
        #expect(result.changedDraft?.id == edited.id)
        #expect(result.changedDraft?.body == "Updated")
        #expect(result.changedDraft?.updatedAt == now)
        #expect(result.limitReached == false)
    }

    @Test
    func saveWithUnchangedBodyReportsNoChange() {
        let edited = Draft(id: UUID(), body: "Same", updatedAt: Date(timeIntervalSince1970: 10))

        let result = DraftPolicy.save(drafts: [edited], editingDraftID: edited.id, body: "Same", maxDrafts: 5, now: Date(timeIntervalSince1970: 100))

        #expect(result.drafts == [edited])
        #expect(result.changedDraft == nil)
        #expect(result.limitReached == false)
    }

    @Test
    func savePersistsImageMetadata() {
        let image = Data("image".utf8)
        let result = DraftPolicy.save(
            drafts: [],
            editingDraftID: nil,
            body: "Post",
            maxDrafts: 5,
            imageData: image,
            imageFilename: "post.png",
            imageMimeType: "image/png"
        )

        #expect(result.changedDraft?.imageData == image)
        #expect(result.changedDraft?.imageFilename == "post.png")
        #expect(result.changedDraft?.imageMimeType == "image/png")
    }

    @Test
    func saveUpdatesImageMetadataWhenBytesAreUnchanged() {
        let image = Data("image".utf8)
        let draft = Draft(body: "Post", imageData: image, imageFilename: "old.jpg", imageMimeType: "image/jpeg")
        let result = DraftPolicy.save(
            drafts: [draft],
            editingDraftID: draft.id,
            body: draft.body,
            maxDrafts: 5,
            imageData: image,
            imageFilename: "post.png",
            imageMimeType: "image/png"
        )

        #expect(result.changedDraft?.imageFilename == "post.png")
        #expect(result.changedDraft?.imageMimeType == "image/png")
    }

    @Test
    func saveWithUnknownEditingIDCreatesNewDraft() {
        let result = DraftPolicy.save(drafts: [], editingDraftID: UUID(), body: "Fresh", maxDrafts: 5, now: Date(timeIntervalSince1970: 100))

        #expect(result.drafts.count == 1)
        #expect(result.changedDraft != nil)
        #expect(result.editingDraftID == result.drafts.first?.id)
        #expect(result.limitReached == false)
    }

    @Test
    func saveBlocksNewDraftAtLimit() {
        let drafts = (0..<5).map { Draft(body: "Draft \($0)") }

        let result = DraftPolicy.save(drafts: drafts, editingDraftID: nil, body: "Overflow", maxDrafts: 5, now: Date(timeIntervalSince1970: 100))

        #expect(result.drafts.count == 5)
        #expect(result.changedDraft == nil)
        #expect(result.limitReached == true)
    }

    @Test
    func deleteRemovesOnlyMatchingDraft() {
        let target = Draft(id: UUID(), body: "Target")
        let other = Draft(id: UUID(), body: "Other")

        let remaining = DraftPolicy.delete([target, other], id: target.id)

        #expect(remaining == [other])
    }

    @Test
    func trimmedBodyRemovesWhitespace() {
        #expect(DraftPolicy.trimmedBody("  hello \n") == "hello")
    }
}
