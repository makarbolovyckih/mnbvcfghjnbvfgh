import SwiftUI

struct ArtworkView: View {
    let song: Song?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { g in
                    if let s = song, let img = ArtworkCache.image(for: s) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: g.size.width, height: g.size.height)
                            .clipped()
                    } else {
                        ZStack {
                            LinearGradient(colors: [Color(.systemGray3), Color(.systemGray5)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: "music.note")
                                .font(.system(size: g.size.width * 0.4))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(width: g.size.width, height: g.size.height)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct SongRow: View {
    let song: Song
    var isCurrent = false
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(song: song, cornerRadius: 6).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? accent : Color.primary)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(accent)
            }
            Text(timeString(song.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

struct SongActions: ViewModifier {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: PlayerModel
    let song: Song
    var playlistID: UUID? = nil

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button { player.playNext(song) } label: { Label("Play Next", systemImage: "text.insert") }
                Button { player.addToQueue(song) } label: { Label("Add to Queue", systemImage: "text.append") }
                Menu {
                    if library.playlists.isEmpty { Text("No playlists yet") }
                    ForEach(library.playlists) { p in
                        Button(p.name) { library.add([song.id], to: p.id) }
                    }
                } label: { Label("Add to Playlist", systemImage: "plus") }
                Button { library.toggleFavorite(song.id) } label: {
                    Label(song.isFavorite ? "Unfavorite" : "Favorite", systemImage: song.isFavorite ? "heart.slash" : "heart")
                }
                if let pid = playlistID {
                    Button(role: .destructive) { library.remove(song.id, from: pid) } label: {
                        Label("Remove from Playlist", systemImage: "minus.circle")
                    }
                }
                Button(role: .destructive) { library.delete([song.id]) } label: {
                    Label("Delete Song", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button { library.toggleFavorite(song.id) } label: {
                    Label("Favorite", systemImage: song.isFavorite ? "heart.slash" : "heart")
                }
                .tint(.pink)
            }
            .swipeActions(edge: .trailing) {
                if let pid = playlistID {
                    Button(role: .destructive) { library.remove(song.id, from: pid) } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                } else {
                    Button(role: .destructive) { library.delete([song.id]) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }
}

extension View {
    func songActions(_ song: Song, playlistID: UUID? = nil) -> some View {
        modifier(SongActions(song: song, playlistID: playlistID))
    }
    func miniPlayer(_ showPlayer: Binding<Bool>) -> some View {
        modifier(MiniPlayerInset(showPlayer: showPlayer))
    }
}

// MARK: Mini player

struct MiniPlayerInset: ViewModifier {
    @Binding var showPlayer: Bool
    @EnvironmentObject var player: PlayerModel

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.current != nil { MiniPlayer(showPlayer: $showPlayer) }
        }
    }
}

struct MiniPlayer: View {
    @EnvironmentObject var player: PlayerModel
    @Binding var showPlayer: Bool

    var body: some View {
        if let song = player.current {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    ArtworkView(song: song, cornerRadius: 6).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { player.togglePlay() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3).frame(width: 38, height: 38)
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.title3).frame(width: 38, height: 38)
                    }
                }
                MiniProgress(clock: player.clock, duration: player.duration)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.08)))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture { showPlayer = true }
        }
    }
}

struct MiniProgress: View {
    @ObservedObject var clock: PlaybackClock
    let duration: Double
    @Environment(\.accent) private var accent

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                Capsule().fill(accent)
                    .frame(width: g.size.width * CGFloat(min(max(clock.time / max(duration, 1), 0), 1)))
            }
        }
        .frame(height: 3)
    }
}

struct SeekBar: View {
    @ObservedObject var clock: PlaybackClock
    let duration: Double
    let onSeek: (Double) -> Void
    @State private var scrubbing = false
    @State private var scrubValue = 0.0

    var body: some View {
        let shown = scrubbing ? scrubValue : clock.time
        VStack(spacing: 4) {
            Slider(value: Binding(get: { shown }, set: { scrubValue = $0 }),
                   in: 0...max(duration, 1),
                   onEditingChanged: { editing in
                       if editing { scrubValue = clock.time; scrubbing = true }
                       else { onSeek(scrubValue); scrubbing = false }
                   })
                .tint(.white)
            HStack {
                Text(timeString(shown))
                Spacer()
                Text("-" + timeString(max(duration - shown, 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}
