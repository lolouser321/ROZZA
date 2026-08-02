import AVFoundation
import Foundation

/// The single owner of ROZZA's process-wide AVAudioSession configuration.
/// Category and mode are set at most once; callers may request reactivation
/// after an interruption without changing the configuration.
@MainActor
final class ROZZAAudioSession {
    static let shared = ROZZAAudioSession()

    private var configured = false
    private var active = false

    private init() {}

    func configureAndActivateIfNeeded() throws {
        let session = AVAudioSession.sharedInstance()

        if !configured {
            print("[ROZZA AudioSession] CALL setCategory(category: playback, mode: default, options: [] / rawValue: 0)")
            do {
                try session.setCategory(.playback, mode: .default, options: [])
                configured = true
                print("[ROZZA AudioSession] OK setCategory")
            } catch {
                logFailure(api: "setCategory(.playback, mode: .default, options: [])", error: error)
                throw error
            }
        } else {
            print("[ROZZA AudioSession] SKIP setCategory — already configured once")
        }

        if !active {
            print("[ROZZA AudioSession] CALL setActive(true), options: [] / rawValue: 0")
            do {
                try session.setActive(true, options: [])
                active = true
                print("[ROZZA AudioSession] OK setActive(true)")
            } catch {
                logFailure(api: "setActive(true, options: [])", error: error)
                throw error
            }
        }

        printDiagnostics(prefix: "activated")
    }

    /// Interruption end may require activation again, but never reconfigures
    /// the category, mode, or options.
    func markInterrupted() { active = false }

    func reactivateAfterInterruption() throws {
        try configureAndActivateIfNeeded()
    }

    func printDiagnostics(prefix: String) {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map {
            "\($0.portName) [\($0.portType.rawValue)]"
        }.joined(separator: ", ")
        print("[ROZZA AudioSession] \(prefix)")
        print("[ROZZA AudioSession] Category:", session.category.rawValue)
        print("[ROZZA AudioSession] Mode:", session.mode.rawValue)
        print("[ROZZA AudioSession] Options rawValue:", session.categoryOptions.rawValue)
        print("[ROZZA AudioSession] Output route:", outputs.isEmpty ? "none" : outputs)
        print("[ROZZA AudioSession] Sample rate:", session.sampleRate)
        print("[ROZZA AudioSession] IO buffer duration:", session.ioBufferDuration)
    }

    private func logFailure(api: String, error: Error) {
        let nsError = error as NSError
        print("[ROZZA AudioSession] FAILED API:", api)
        print("[ROZZA AudioSession] NSError domain:", nsError.domain)
        print("[ROZZA AudioSession] NSError code / OSStatus:", nsError.code)
        print("[ROZZA AudioSession] NSError description:", nsError.localizedDescription)
        print("[ROZZA AudioSession] NSError userInfo:", nsError.userInfo)
    }
}
