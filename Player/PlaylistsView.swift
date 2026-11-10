import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var library: Library
    @Binding var showPlayer: Bool
    @State private var creating = false
    @State private var newName = ""
    @State private var showRename = false
    @State private var renameID: UUID?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SongCollectionView(source: .favorites)
                    } label: {
                        Label { Text("Favorites") } icon: { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                    }
                }
                Section("Playlists") {
                    if library.playlists.isEmpty {
                        Text("Tap + to create a playlist.").foregroundStyle(.secondary)
                    }
                    ForEach(library.playlists) { p in
                        NavigationLink {
                            SongCollectionView(source: .playlist(p.id))
                        } label: {
                            PlaylistRow(playlist: p)
                        }
                        .contextMenu {
                            Button { renameID = p.id; renameText = p.name; showRename = true } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) { library.deletePlaylist(p.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { library.deletePlaylists(at: $0) }
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; creating = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("New Playlist", isPresented: $creating) {
                TextField("Playlist name", text: $newName)
                Button("Create") { library.createPlaylist(newName) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename Playlist", isPresented: $showRename) {
                TextField("Name", text: $renameText)
                Button("Save") { if let id = renameID { library.rename(id, to: renameText) } }
                Button("Cancel", role: .cancel) {}
            }
        }
        .miniPlayer($showPlayer)
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    @EnvironmentObject var library: Library

    var body: some View {
        let first = playlist.songIDs.first.flatMap { library.song($0) }
        HStack(spacing: 12) {
            ArtworkView(song: first, cornerRadius: 6).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).lineLimit(1)
                Text("\(playlist.songIDs.count) song\(playlist.songIDs.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SongCollectionView: View {
    enum Source { case favorites, playlist(UUID) }
    let source: Source
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: PlayerModel
    @State private var adding = false

    private var playlist: Playlist? {
        if case .playlist(let id) = source { return library.playlists.first { $0.id == id } }
        return nil
    }
    private var playlistID: UUID? { playlist?.id }
    private var songs: [Song] {
        switch source {
        case .favorites: return library.favorites
        case .playlist: return playlist.map { library.songs(in: $0) } ?? []
        }
    }
    private var title: String {
        if case .favorites = source { return "Favorites" }
        return playlist?.name ?? "Playlist"
    }

    var body: some View {
        List {
            if !songs.isEmpty {
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
                    .songActions(song, playlistID: playlistID)
                    .deleteDisabled(playlistID == nil)
                    .moveDisabled(playlistID == nil)
                }
                .onDelete { offsets in
                    if let pid = playlistID { library.removeSongs(at: offsets, from: pid) }
                }
                .onMove { from, to in
                    if let pid = playlistID { library.moveSongs(from: from, to: to, in: pid) }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if songs.isEmpty {
                ContentUnavailableView(playlistID == nil ? "No Favorites" : "Empty Playlist",
                                       systemImage: playlistID == nil ? "heart" : "music.note.list",
                                       description: Text(playlistID == nil ? "Tap the heart on a song to add it here."
                                                                           : "Tap + to add songs."))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if playlistID != nil {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $adding) {
            if let pid = playlistID { AddSongsView(playlistID: pid) }
        }
    }
}

struct AddSongsView: View {
    let playlistID: UUID
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var selected = Set<UUID>()

    private var available: [Song] {
        let existing = Set(library.playlists.first { $0.id == playlistID }?.songIDs ?? [])
        return library.songs
            .filter { !existing.contains($0.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(available) { song in
                Button {
                    if selected.contains(song.id) { selected.remove(song.id) } else { selected.insert(song.id) }
                } label: {
                    HStack {
                        SongRow(song: song)
                        Image(systemName: selected.contains(song.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(song.id) ? accent : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay {
                if available.isEmpty {
                    ContentUnavailableView("No More Songs", systemImage: "music.note",
                                           description: Text("Every song is already in this playlist."))
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add (\(selected.count))") {
                        library.add(available.filter { selected.contains($0.id) }.map { $0.id }, to: playlistID)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
