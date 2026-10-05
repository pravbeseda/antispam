import Foundation
import Testing
@testable import AntispamCore

private final class Recorder: @unchecked Sendable {
    var request: URLRequest?
}

private func client(status: Int = 200, response: String, recorder: Recorder = Recorder()) -> JevClient {
    JevClient(apiKey: "test-key") { request in
        recorder.request = request
        let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(response.utf8), http)
    }
}

private let phishingResponse = """
{"model":"jev-1.13.0","answers":{"category":{"type":"choice","choice":"phishing","confidence":0.93,
"probabilities":{"spam":0.05,"phishing":0.94,"promo":0.0,"legit":0.01}}},"usage":{"input_tokens":900,"output_tokens":40}}
"""

private let sampleMessage = MIMEParser.parse(Data("""
From: PayPal <service@paypa1.example>\r
Reply-To: thief@example.net\r
Received: from somewhere\r
Subject: Account locked\r
Authentication-Results: mx; spf=fail\r
Authentication-Results: mx; dkim=none\r
\r
\(String(repeating: "x", count: 9000)) https://paypa1.example/login\r
""".utf8))

@Suite struct JevClientTests {
    @Test func buildsChoiceRequest() async throws {
        let recorder = Recorder()
        _ = try await client(response: phishingResponse, recorder: recorder).classify(sampleMessage)

        let request = try #require(recorder.request)
        #expect(request.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.timeoutInterval == 10)

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "jev-1.13.0")

        let email = try #require((json["state"] as? [String: Any])?["email"] as? [String: Any])
        let headers = try #require(email["headers"] as? [String: String])
        #expect(headers == [
            "From": "PayPal <service@paypa1.example>",
            "Reply-To": "thief@example.net",
            "Subject": "Account locked",
            "Authentication-Results": "mx; spf=fail\nmx; dkim=none",
        ])
        #expect((email["body"] as? String)?.count == 8000)
        #expect(email["link_domains"] as? [String] == ["paypa1.example"])

        let question = try #require((json["questions"] as? [String: Any])?["category"] as? [String: Any])
        #expect(question["type"] as? String == "choice")
        #expect(question["instructions"] is String)
        let criteria = try #require(question["criteria"] as? [String: String])
        #expect(Set(criteria.keys) == ["spam", "phishing", "promo", "legit"])
    }

    @Test func parsesChoiceAndConfidence() async throws {
        let result = try await client(response: phishingResponse).classify(sampleMessage)
        #expect(result == Classification(category: .phishing, confidence: 0.93))
    }

    @Test func nonSuccessStatusThrows() async {
        await #expect(throws: JevError.http(status: 429)) {
            try await client(status: 429, response: "{}").classify(sampleMessage)
        }
    }

    @Test func unknownChoiceThrows() async {
        let response = #"{"answers":{"category":{"type":"choice","choice":"other","confidence":1.0}}}"#
        await #expect(throws: JevError.invalidResponse) {
            try await client(response: response).classify(sampleMessage)
        }
    }
}
