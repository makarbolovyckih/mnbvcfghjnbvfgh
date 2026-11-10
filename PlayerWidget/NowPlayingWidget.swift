import WidgetKit
import SwiftUI
import AppIntents

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot?
    let artwork: UIImage?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(),
                        snapshot: NowPlayingSnapshot(title: "Song Title", artist: "Artist", isPlaying: true, songID: "", hasArtwork: false),
                        artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> NowPlayingEntry {
        let snap = SharedStore.readSnapshot()
        let art = (snap?.hasArtwork ?? false) ? SharedStore.readArtwork() : nil
        return NowPlayingEntry(date: Date(), snapshot: snap, artwork: art)
    }
}

struct NowPlayingWidget: Widget {
    let kind = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("See what's playing and control it from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct PlayerWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
    }
}

// MARK: Views

struct NowPlayingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    private var title: String { entry.snapshot?.title ?? "Not Playing" }
    private var artist: String { entry.snapshot?.artist ?? "Tap play to resume" }
    private var isPlaying: Bool { entry.snapshot?.isPlaying ?? false }

    var body: some View {
        Group {
            if family == .systemSmall { small } else { medium }
        }
        .containerBackground(for: .widget) { background }
    }

    // Small: artwork fills the widget, controls sit on a dark gradient
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(artist).font(.system(size: 12)).opacity(0.75).lineLimit(1)
            }
            .padding(.bottom, 6)
            HStack(spacing: 0) {
                Button(intent: PreviousTrackIntent()) { icon("backward.fill", size: 17) }
                Spacer(minLength: 0)
                Button(intent: TogglePlayIntent()) { icon(isPlaying ? "pause.fill" : "play.fill", size: 24) }
                Spacer(minLength: 0)
                Button(intent: NextTrackIntent()) { icon("forward.fill", size: 17) }
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(14)
    }

    // Medium: artwork on the left, info + controls on the right
    private var medium: some View {
        HStack(spacing: 14) {
            artworkTile
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                Text(artist).font(.system(size: 13)).opacity(0.75).lineLimit(1).padding(.top, 2)
                Spacer(minLength: 4)
                HStack(spacing: 0) {
                    Button(intent: PreviousTrackIntent()) { icon("backward.fill", size: 22) }
                    Spacer(minLength: 0)
                    Button(intent: TogglePlayIntent()) { icon(isPlaying ? "pause.fill" : "play.fill", size: 30) }
                    Spacer(minLength: 0)
                    Button(intent: NextTrackIntent()) { icon("forward.fill", size: 22) }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(16)
    }

    private func icon(_ name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size))
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var artworkTile: some View {
        if let art = entry.artwork {
            Image(uiImage: art).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [Color(white: 0.35), Color(white: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: 40)).foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    @ViewBuilder private var background: some View {
        if let art = entry.artwork {
            if family == .systemSmall {
                ZStack {
                    Image(uiImage: art).resizable().scaledToFill()
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                }
            } else {
                ZStack {
                    Image(uiImage: art).resizable().scaledToFill().blur(radius: 30)
                    Color.black.opacity(0.45)
                }
            }
        } else {
            LinearGradient(colors: [Color(white: 0.28), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
        }
    }
}
