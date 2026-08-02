import SwiftUI
import UniformTypeIdentifiers

struct DJLauncherButton: View {
    @ObservedObject var controller: DJPlaybackController

    var body: some View {
        Button { controller.isPresented = true } label: {
            Label("DJ", systemImage: "slider.horizontal.3")
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(.black.opacity(0.8), in: Capsule())
                .foregroundStyle(.orange)
        }
        .padding(.top, 12).padding(.trailing, 10)
        .sheet(isPresented: $controller.isPresented) { DJTestView(controller: controller) }
    }
}

struct DJTestView: View {
    @ObservedObject var controller: DJPlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var directURL = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    deck(
                        title: "Deck A · YouTube",
                        subtitle: controller.youtubeReady ? "Player ready" : "Open and start a YouTube track in ROZZA first",
                        playing: controller.isYouTubePlaying,
                        volume: Binding(get: { controller.youtubeDeckVolume }, set: controller.setYouTubeDeckVolume),
                        play: controller.playYouTube,
                        pause: { controller.pauseYouTube() }
                    )
                    deck(
                        title: "Deck B · AVPlayer",
                        subtitle: controller.deckBName,
                        playing: controller.isAVPlayerPlaying,
                        volume: Binding(get: { controller.avDeckVolume }, set: controller.setAVDeckVolume),
                        play: controller.playAVPlayer,
                        pause: { controller.pauseAVPlayer() }
                    )

                    HStack {
                        Button("Import MP3/M4A") { importing = true }.buttonStyle(.borderedProminent).tint(.orange)
                        TextField("Direct audio URL", text: $directURL).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                        Button("Load") { controller.loadDirectURL(directURL) }.buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("CROSSFADER").font(.caption.bold()).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { controller.crossfader }, set: controller.setCrossfader), in: 0...1)
                            .tint(.orange)
                        HStack { Text("YouTube"); Spacer(); Text("70 / 70"); Spacer(); Text("AVPlayer") }
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    debugPanel
                    if let error = controller.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .background(Color.black)
            .foregroundStyle(.white)
            .navigationTitle("ROZZA DJ Test")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { controller.importLocalFile(url) }
        }
    }

    private func deck(title: String, subtitle: String, playing: Bool, volume: Binding<Float>, play: @escaping () -> Void, pause: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Button(action: play) { Label("Play", systemImage: "play.fill") }.buttonStyle(.borderedProminent).tint(.orange)
                Button(action: pause) { Label("Pause", systemImage: "pause.fill") }.buttonStyle(.bordered)
            }
            HStack { Image(systemName: "speaker.slash.fill"); Slider(value: volume, in: 0...1).tint(.orange); Image(systemName: "speaker.wave.3.fill"); Text("\(Int(volume.wrappedValue * 100))").monospacedDigit().frame(width: 32) }
        }
        .padding().background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("LIVE DEBUG").font(.caption.bold()).foregroundStyle(.orange)
            debug("YouTube ready", controller.youtubeReady ? "true" : "false")
            debug("YouTube requested", percent(controller.youtubeRequestedVolume))
            debug("YouTube reported", percent(controller.youtubeReportedVolume))
            debug("AVPlayer requested", percent(controller.avRequestedVolume))
            debug("AVPlayer actual", percent(controller.avActualVolume))
            debug("Output route", controller.outputRoute)
            debug("System volume (display only)", percent(controller.systemOutputVolume))
        }
        .font(.caption.monospaced()).padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func debug(_ label: String, _ value: String) -> some View { HStack(alignment: .top) { Text(label + ":").foregroundStyle(.secondary); Text(value).textSelection(.enabled) } }
    private func percent(_ value: Float) -> String { "\(Int((value * 100).rounded()))%" }
}
