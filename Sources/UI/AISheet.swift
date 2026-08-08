import SwiftUI

private struct ChatMessage: Identifiable { let id = UUID(); let user: Bool; let text: String; let tracks: [Track] }

struct AISheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var loading = false
    @State private var messages = [ChatMessage(user: false, text: "Good evening. I am ROZZA AI. Tell me what music you want—in Arabic, English, or Franco-Arabic.", tracks: [])]
    private let sessionID = UUID().uuidString
    private let prompts = ["Play Egyptian songs for a party", "Give me something relaxing", "Play Amr Diab songs", "Egyptian wedding music", "Something energetic but not mahraganat", "Make me a gym playlist"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let track = env.playback.currentTrack { Label { Text("Now: \(track.title) — \(track.artist)").lineLimit(1) } icon: { Image(systemName: "music.note") }.font(.caption).foregroundStyle(Theme.secondary).padding().frame(maxWidth: .infinity, alignment: .leading).background(Theme.accent.opacity(0.08)) }
                ScrollViewReader { reader in ScrollView { LazyVStack(spacing: 10) { ForEach(messages) { message in messageView(message) }; if loading { HStack { ProgressView(); Text("Searching real music…") }.padding().background(Theme.elevated).clipShape(RoundedRectangle(cornerRadius: 18)).frame(maxWidth: .infinity, alignment: .leading) }; if messages.count == 1 { promptGrid } }.padding() }.onChange(of: messages.count) { _, _ in if let id = messages.last?.id { withAnimation { reader.scrollTo(id, anchor: .bottom) } } } }
                HStack { TextField("Ask in Arabic, English, or Franco-Arabic…", text: $input, axis: .vertical).lineLimit(1...3).padding(.horizontal, 15).padding(.vertical, 11).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 22)); Button { Task { await send(input) } } label: { Image(systemName: "paperplane.fill").frame(width: 44, height: 44).background(Theme.accent).foregroundStyle(.white).clipShape(Circle()) }.disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || loading) }.padding()
            }.navigationTitle("ROZZA AI Intelligence").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }.premiumBackground()
        }
    }
    private func messageView(_ message: ChatMessage) -> some View { VStack(alignment: message.user ? .trailing : .leading, spacing: 8) { Text(message.text).padding(14).background(message.user ? Theme.accent : Theme.elevated).clipShape(RoundedRectangle(cornerRadius: 18)).frame(maxWidth: .infinity, alignment: message.user ? .trailing : .leading); ForEach(message.tracks.prefix(4)) { track in TrackRow(track: track) { Task { await env.playback.play(track, in: message.tracks); env.playback.isFullPlayerPresented = true } } } }.id(message.id) }
    private var promptGrid: some View { VStack(alignment: .leading, spacing: 10) { Text("QUICK AI MUSIC PROMPTS").font(.caption.bold()).foregroundStyle(Theme.secondary); FlowLayout(spacing: 8) { ForEach(prompts, id: \.self) { prompt in Button { Task { await send(prompt) } } label: { Label(prompt, systemImage: "sparkles").font(.caption).padding(.horizontal, 12).padding(.vertical, 9).background(.white.opacity(0.05)).clipShape(Capsule()).overlay(Capsule().stroke(.white.opacity(0.1))) } } } }.padding(.top) }
    private func send(_ value: String) async { let clean = value.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty else { return }; input = ""; messages.append(.init(user: true, text: clean, tracks: [])); loading = true; defer { loading = false }; do { let result = try await AIService(api: env.api).chat(message: clean, sessionID: sessionID, currentTrack: env.playback.currentTrack); messages.append(.init(user: false, text: result.message, tracks: result.tracks)) } catch { messages.append(.init(user: false, text: "ROZZA AI is temporarily unavailable. \(error.localizedDescription)", tracks: [])) } }
}

struct FlowLayout: Layout {
    let spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { arrange(width: proposal.width ?? 0, subviews: subviews).size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) { let result = arrange(width: bounds.width, subviews: subviews); for item in result.items { item.view.place(at: CGPoint(x: bounds.minX + item.point.x, y: bounds.minY + item.point.y), proposal: .unspecified) } }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, items: [(view: LayoutSubview, point: CGPoint)]) { var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0; var items: [(LayoutSubview, CGPoint)] = []; for view in subviews { let size = view.sizeThatFits(.unspecified); if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }; items.append((view, CGPoint(x: x, y: y))); x += size.width + spacing; row = max(row, size.height) }; return (CGSize(width: width, height: y + row), items) }
}

