import Foundation

/// URLProtocol subclass that intercepts requests and returns a canned response.
///
/// Swift Testing runs suites in parallel, so the shared static `requestHandler`
/// would race across suites. Tests must hold `MockURLProtocol.suiteLock` for
/// their lifetime to serialize access. The typical pattern in a test class:
///
///     init() {
///         MockURLProtocol.suiteLock.lock()
///         MockURLProtocol.requestHandler = nil
///         session = .mock()
///     }
///
///     deinit {
///         MockURLProtocol.requestHandler = nil
///         MockURLProtocol.suiteLock.unlock()
///     }
final class MockURLProtocol: URLProtocol {
    /// Held by every test that uses this mock, so suites can't race on the
    /// shared `requestHandler` slot. Acquire in init, release in deinit.
    static let suiteLock = NSLock()

    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: MockError.handlerNotSet)
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

    enum MockError: Error {
        case handlerNotSet
    }
}

extension URLSession {
    static func mock() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
