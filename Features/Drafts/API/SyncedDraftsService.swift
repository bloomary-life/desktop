import CryptoKit
import Foundation

protocol DraftSyncing {
    func listDrafts(memberID: String, accessToken: String) async throws -> [Draft]
    func upsertDraft(_ draft: Draft, memberID: String, accessToken: String) async throws -> Draft
    func deleteDraft(id: Draft.ID, memberID: String, accessToken: String) async throws
}

final class SyncedDraftsService: DraftSyncing {
    private let apiBaseURL: URL
    private let session: URLSession

    init(apiBaseURL: URL, session: URLSession = .shared) {
        self.apiBaseURL = apiBaseURL
        self.session = session
    }

    func listDrafts(memberID: String, accessToken: String) async throws -> [Draft] {
        let response = try await sync(memberID: memberID, accessToken: accessToken)
        return try await response.drafts.asyncCompactMap { try await draft(from: $0) }
    }

    func upsertDraft(_ draft: Draft, memberID: String, accessToken: String) async throws -> Draft {
        let upsert = try await draftSyncUpsert(draft, memberID: memberID, accessToken: accessToken)
        let response = try await sync(
            upserts: [upsert],
            memberID: memberID,
            accessToken: accessToken
        )
        guard let synced = response.drafts.first(where: { $0.draftId.lowercased() == draft.id.uuidString.lowercased() }) else { return draft }
        return try await self.draft(from: synced) ?? draft
    }

    func deleteDraft(id: Draft.ID, memberID: String, accessToken: String) async throws {
        _ = try await sync(deletes: [id.uuidString], memberID: memberID, accessToken: accessToken)
    }

    private func sync(
        upserts: [DraftSyncUpsert] = [],
        deletes: [String] = [],
        memberID: String,
        accessToken: String
    ) async throws -> DraftsResponse {
        var request = authorizedRequest(path: "/api/drafts/sync", memberID: memberID, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.app.encode(DraftSyncRequest(upserts: upserts, deletes: deletes))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder.app.decode(DraftsResponse.self, from: data)
    }

    private func draftSyncUpsert(_ draft: Draft, memberID: String, accessToken: String) async throws -> DraftSyncUpsert {
        guard let imageData = draft.imageData else {
            return DraftSyncUpsert(draftId: draft.id.uuidString, body: draft.body, updatedAt: draft.updatedAt)
        }
        let mimeType = draft.imageMimeType ?? "image/jpeg"
        let checksum = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
        var request = authorizedRequest(path: "/api/draft-images/presign-upload", memberID: memberID, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.app.encode(DraftImagePresignUploadRequest(draftId: draft.id.uuidString, mimeType: mimeType, sizeBytes: Int64(imageData.count), checksumSHA256: checksum))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let presign = try JSONDecoder.app.decode(DraftImagePresignUploadResponse.self, from: data)
        guard let uploadURL = URL(string: presign.uploadUrl) else { throw SyncedDraftsError.server("Draft image upload URL is invalid.") }
        var upload = URLRequest(url: uploadURL)
        upload.httpMethod = "PUT"
        presign.headers.forEach { upload.setValue($0.value, forHTTPHeaderField: $0.key) }
        upload.httpBody = imageData
        let (uploadData, uploadResponse) = try await session.data(for: upload)
        try validateUpload(response: uploadResponse, data: uploadData)
        return DraftSyncUpsert(draftId: draft.id.uuidString, body: draft.body, updatedAt: draft.updatedAt, image: DraftSyncImage(imageId: presign.imageId, downloadUrl: nil, mimeType: mimeType, sizeBytes: Int64(imageData.count), checksumSHA256: checksum))
    }

    private func draft(from synced: SyncedDraft) async throws -> Draft? {
        guard let uuid = UUID(uuidString: synced.draftId) else { return nil }
        var imageData: Data?
        if let image = synced.image, let value = image.downloadUrl, let url = URL(string: value) {
            let (data, response) = try await session.data(from: url)
            try validateUpload(response: response, data: data)
            imageData = data
        }
        return Draft(id: uuid, body: synced.body, imageData: imageData, imageFilename: synced.image.map { "\($0.imageId).\(fileExtension(for: $0.mimeType))" }, imageMimeType: synced.image?.mimeType, createdAt: synced.createdAt, updatedAt: synced.updatedAt)
    }

    private func validateUpload(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) else { return }
        let apiError = try? JSONDecoder.app.decode(SyncedDraftsAPIError.self, from: data)
        throw SyncedDraftsError.server(apiError?.errorDescription ?? apiError?.error ?? "Draft image transfer failed.")
    }

    private func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/heic": return "heic"
        case "image/webp": return "webp"
        default: return "jpg"
        }
    }

    private func authorizedRequest(path: String, memberID: String, accessToken: String) -> URLRequest {
        let url = apiBaseURL.appending(path: path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "memberId", value: memberID)]
        var request = URLRequest(url: components?.url ?? url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 402 || http.statusCode == 403 {
                throw SyncedDraftsError.entitlementRequired
            }
            if let apiError = try? JSONDecoder.app.decode(SyncedDraftsAPIError.self, from: data) {
                throw SyncedDraftsError.server(apiError.errorDescription ?? apiError.error)
            }
            throw SyncedDraftsError.server("Draft sync failed.")
        }
    }
}

enum SyncedDraftsError: LocalizedError {
    case server(String)
    /// 402/403: the account is not entitled to draft sync. Terminal for the
    /// mutation — degrade gracefully, never retry and never touch local drafts.
    case entitlementRequired

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        case .entitlementRequired:
            return "Draft sync is not available for this account."
        }
    }
}

private struct DraftsResponse: Decodable {
    let drafts: [SyncedDraft]
}

private struct DraftSyncRequest: Encodable {
    let upserts: [DraftSyncUpsert]
    let deletes: [String]
}

private struct DraftSyncUpsert: Encodable {
    let draftId: String
    let body: String
    let updatedAt: Date
    let image: DraftSyncImage?

    init(draftId: String, body: String, updatedAt: Date, image: DraftSyncImage? = nil) {
        self.draftId = draftId
        self.body = body
        self.updatedAt = updatedAt
        self.image = image
    }
}

private struct SyncedDraft: Decodable {
    let draftId: String
    let body: String
    let image: DraftSyncImage?
    let createdAt: Date
    let updatedAt: Date

}

private struct DraftSyncImage: Codable {
    let imageId: String
    let downloadUrl: String?
    let mimeType: String
    let sizeBytes: Int64
    let checksumSHA256: String
}

private struct DraftImagePresignUploadRequest: Encodable {
    let draftId: String
    let mimeType: String
    let sizeBytes: Int64
    let checksumSHA256: String
}

private struct DraftImagePresignUploadResponse: Decodable {
    let imageId: String
    let uploadUrl: String
    let headers: [String: String]
}

private struct SyncedDraftsAPIError: Decodable {
    let error: String
    let errorDescription: String?
}

private extension Array {
    func asyncCompactMap<T>(_ transform: (Element) async throws -> T?) async throws -> [T] {
        var values: [T] = []
        for element in self {
            if let value = try await transform(element) { values.append(value) }
        }
        return values
    }
}
