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
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: player.current != nil)
    }
}

struct MiniPlayer: View {
    @EnvironmentObject var player: PlayerModel
    @Binding var showPlayer: Bool
    @State private var dragX: CGFloat = 0

    var body: some View {
        if let song = player.current {
            HStack(spacing: 12) {
                ArtworkView(song: song, cornerRadius: 8)
                    .frame(width: 42, height: 42)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)

                Text(song.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MiniPlayerButtonStyle())

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 22))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MiniPlayerButtonStyle())
            }
            .foregroundStyle(.primary)
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 58)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .offset(x: dragX)
            .contentShape(Rectangle())
            .onTapGesture { showPlayer = true }
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { v in
                        if abs(v.translation.width) > abs(v.translation.height) {
                            dragX = v.translation.width / 3
                        }
                    }
                    .onEnded { v in
                        let dx = v.translation.width, dy = v.translation.height
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragX = 0 }
                        if dy < -30, abs(dy) > abs(dx) {
                            showPlayer = true
                        } else if dx < -60 {
                            player.next()
                        } else if dx > 60 {
                            player.previous()
                        }
                    }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct MiniPlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
