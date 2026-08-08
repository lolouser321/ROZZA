import Foundation
import AVFoundation

@MainActor
protocol PlaybackProvider: AnyObject {
    var source: ContentSource { get }
    var supportsNativeBackground: Bool { get }
    func load(_ track: Track) async throws
    func play() async throws
    func pause()
    func seek(to seconds: TimeInterval) async
    func stop()
}

protocol SearchProvider: Sendable {
    var source: ContentSource { get }
    func search(query: String, filter: SearchFilter, pageToken: String?) async throws -> SearchPage
    func suggestions(for query: String) async throws -> [String]
}

enum ROZZAError: LocalizedError {
    case invalidConfiguration, unsupportedPlayback, network(String), invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "ROZZA's backend is not configured."
        case .unsupportedPlayback: "This source cannot play in the requested mode."
        case .network(let message): message
        case .invalidResponse: "The server returned an invalid response."
        }
    }
}

