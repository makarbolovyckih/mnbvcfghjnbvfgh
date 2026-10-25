import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: PlayerModel
    @Binding var showPlayer: Bool
    @State private var search = ""
    @State private var importing = false
    @AppStorage("sortOrder") private var sortOrder = SortOrder.title.rawValue

    private var songs: [Song] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? library.songs : library.songs.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.artist.localizedCaseInsensitiveContains(q) ||
            $0.album.localizedCaseInsensitiveContains(q)
        }
        switch SortOrder(rawValue: sortOrder) ?? .title {
        case .title: return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist: return filtered.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .recent: return filtered.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.songs.isEmpty {
                    ContentUnavailableView {
                        Label("No Songs", systemImage: "music.note")
                    } description: {
                        Text("Add songs from the Files app to build your library.")
                    } actions: {
                        Button("Add Songs") { importing = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if search.isEmpty {
                            Section {
                                HStack(spacing: 12) {
                                    Button { player.play(songs, shuffle: false) } label: {
                                        Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                                    }
                                    Button { player.play(songs, shuffle: true) } label: {
                                        Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            }
                        }
                        Section {
                            ForEach(songs) { song in
                                Button { player.play(songs, startingAt: song) } label: {
                                    SongRow(song: song, isCurrent: player.current?.id == song.id)
                                }
                                .buttonStyle(.plain)
                                .songActions(song)
                            }
                        } footer: {
                            Text("\(library.songs.count) song\(library.songs.count == 1 ? "" : "s")")
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Library")
            .searchable(text: $search, prompt: "Songs, artists, albums")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort By", selection: $sortOrder) {
                            ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { library.importFiles(urls) }
            }
        }
        .miniPlayer($showPlayer)
    }
}
