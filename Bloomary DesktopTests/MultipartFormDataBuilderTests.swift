import Foundation
import Testing
@testable import Bloomary_Desktop

struct MultipartFormDataBuilderTests {
    @Test
    func buildsExpectedFormBody() throws {
        let builder = MultipartFormDataBuilder(boundary: "test-boundary")
        let data = builder.body(fields: ["commentary": "Hello"])
        let body = try #require(String(data: data, encoding: .utf8))

        #expect(body.contains("--test-boundary\r\n"))
        #expect(body.contains("Content-Disposition: form-data; name=\"commentary\"\r\n\r\n"))
        #expect(body.contains("Hello\r\n"))
        #expect(body.hasSuffix("--test-boundary--\r\n"))
    }

    @Test
    func includesImageAttachment() throws {
        let data = MultipartFormDataBuilder(boundary: "test-boundary").body(
            fields: ["commentary": "Hello"],
            file: MultipartFormFile(fieldName: "attachment", filename: "post.png", mimeType: "image/png", data: Data("image".utf8))
        )
        let body = try #require(String(data: data, encoding: .utf8))

        #expect(body.contains("name=\"attachment\"; filename=\"post.png\""))
        #expect(body.contains("Content-Type: image/png\r\n\r\nimage\r\n"))
    }
}
