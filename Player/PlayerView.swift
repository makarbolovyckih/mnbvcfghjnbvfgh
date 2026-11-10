import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var player: PlayerModel
    @EnvironmentObject var library: Library
    @Environment(\.accent) private var accent
    @Environment(\.dismiss) private var dismiss
    @State private var showEQ = false
    @State private var showQueue = false

    var body: some View {
        Group {
            if let song = player.current {
                content(song)
            } else {
                Text("Nothing Playing").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { background }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .onChange(of: player.queue.isEmpty) { _, empty in if empty { dismiss() } }
        .sheet(isPresented: $showEQ) {
            EQView().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showQueue) { QueueView() }
    }

    @ViewBuilder private var background: some View {
        ZStack {
            Color.black
            if let s = player.current, let img = ArtworkCache.image(for: s) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .blur(radius: 70)
                    .opacity(0.65)
            } else {
                LinearGradient(colors: [accent.opacity(0.6), .black], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }

    private func content(_ song: Song) -> some View {
        let isFav = library.song(song.id)?.isFavorite ?? false
        return GeometryReader { geo in
            let side = max(min(geo.size.width - 56, geo.size.height * 0.42), 120)
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                ArtworkView(song: song, cornerRadius: 14)
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
                    .scaleEffect(player.isPlaying ? 1 : 0.88)
                    .animation(.spring(response: 0.45, dampingFraction: 0.7), value: player.isPlaying)
                Spacer(minLength: 20)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.title3.bold()).lineLimit(1)
                        Text(song.artist).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { library.toggleFavorite(song.id) } label: {
                        Image(systemName: isFav ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(isFav ? accent : Color.white)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.bottom, 12)

                SeekBar(clock: player.clock, duration: player.duration) { player.seek(to: $0) }

                Spacer(minLength: 12)
                controls
                Spacer(minLength: 12)

                HStack {
                    Button { showEQ = true } label: {
                        Image(systemName: "slider.vertical.3").font(.title3)
                            .foregroundStyle(player.eqEnabled ? accent : Color.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Button { showQueue = true } label: {
                        Image(systemName: "list.bullet").font(.title3)
                            .foregroundStyle(Color.white.opacity(0.9))
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 28)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var controls: some View {
        HStack {
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle").font(.title3)
                    .foregroundStyle(player.isShuffled ? accent : Color.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(player.isShuffled ? accent.opacity(0.2) : Color.clear, in: Circle())
            }
            Spacer()
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 34))
            }
            Spacer()
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 76))
            }
            Spacer()
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 34))
            }
            Spacer()
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").font(.title3)
                    .foregroundStyle(player.repeatMode == .off ? Color.white.opacity(0.7) : accent)
                    .frame(width: 44, height: 44)
                    .background(player.repeatMode == .off ? Color.clear : accent.opacity(0.2), in: Circle())
            }
        }
        .foregroundStyle(.white)
    }
}
