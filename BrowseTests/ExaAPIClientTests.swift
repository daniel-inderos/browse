import Foundation
import Testing
@testable import Browse

@Suite("ExaAPIClient")
struct ExaAPIClientTests {
    @Test("Search authenticates with x-api-key header")
    func searchUsesXAPIKeyHeader() async throws {
        let session = URLSession(configuration: Self.mockSessionConfiguration())
        let client = ExaAPIClient(getAPIKey: { "test-exa-key" }, session: session)

        MockURLProtocol.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-exa-key")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            let data = try #require(#"{"requestId":"request-1","results":[]}"#.data(using: .utf8))
            return (response, data)
        }

        let response = try await client.search(query: "swift ui", numResults: 1)
        #expect(response.requestId == "request-1")
        #expect(response.results.isEmpty)
    }

    private static func mockSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
