import Foundation

/// Simuliertes Netzwerk: beantwortet Anfragen über einen Handler und protokolliert sie.
/// Statischer Zustand – Tests, die ihn nutzen, laufen in einer serialisierten Suite.
nonisolated final class StubURLProtocol: URLProtocol {
  typealias Handler = @Sendable (URLRequest) -> (status: Int, body: String)

  private static let lock = NSLock()
  private nonisolated(unsafe) static var handler: Handler?
  private nonisolated(unsafe) static var recorded: [URLRequest] = []

  static func install(_ handler: @escaping Handler) {
    lock.withLock {
      self.handler = handler
      recorded = []
    }
  }

  static var requests: [URLRequest] {
    lock.withLock { recorded }
  }

  static func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let handler = Self.lock.withLock {
      Self.recorded.append(request)
      return Self.handler
    }
    guard let handler, let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    let (status, body) = handler(request)
    guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
