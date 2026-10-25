import SwiftUI
import AVFoundation

@MainActor
final class Library: ObservableObject {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf", "alac"]

    @Published var songs: [Song] = [] { didSet { save(songs, "songs.json") } }
    @Published var playlists: [Playlist] = [] { didSet { save(playlists, "playlists.json") } }
    var onDelete: ((UUID) -> Void)?

    init() {
        let loaded: [Song] = Library.load("songs.json") ?? []
        songs = loaded.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        playlists = Library.load("playlists.json") ?? []
    }

    // MARK: Persistence
    private static func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: Paths.support.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func save<T: Encodable>(_ value: T, _ name: String) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: Paths.support.appendingPathComponent(name), options: .atomic)
        }
    }

    // MARK: Importing
    func importFiles(_ urls: [URL]) {
        Task {
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                await addFile(url, move: false)
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    /// Audio files dropped into the app's folder in the Files app get picked up here.
    func scanDropFolder() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: Paths.documents, includingPropertiesForKeys: nil) else { return }
        let audio = files.filter { Library.audioExtensions.contains($0.pathExtension.lowercased()) }
        guard !audio.isEmpty else { return }
        Task { for f in audio { await addFile(f, move: true) } }
    }

    private func addFile(_ source: URL, move: Bool) async {
        let ext = source.pathExtension.lowercased()
        guard Library.audioExtensions.contains(ext) else { return }
        let id = UUID()
        let fileName = "\(id.uuidString).\(ext)"
        let dest = Paths.songs.appendingPathComponent(fileName)
        do {
            if move { try FileManager.default.moveItem(at: source, to: dest) }
            else { try FileManager.default.copyItem(at: source, to: dest) }
        } catch { return }

        let asset = AVURLAsset(url: dest)
        var title = source.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var hasArt = false
        var duration = 0.0
        if let d = try? await asset.load(.duration), d.seconds.isFinite { duration = d.seconds }
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                let ident = item.identifier
                if ident == .commonIdentifierTitle {
                    if let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
                } else if ident == .commonIdentifierArtist {
                    if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
                } else if ident == .commonIdentifierAlbumName {
                    if let v = try? await item.load(.stringValue), !v.isEmpty { album = v }
                } else if ident == .commonIdentifierArtwork {
                    if let data = try? await item.load(.dataValue), let img = UIImage(data: data) {
                        hasArt = saveArtwork(img, id: id)
                    }
                }
            }
        }
        songs.append(Song(id: id, fileName: fileName, title: title, artist: artist, album: album,
                          duration: duration, hasArtwork: hasArt))
    }

    private func saveArtwork(_ img: UIImage, id: UUID) -> Bool {
        let maxSide: CGFloat = 800
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = small.jpegData(compressionQuality: 0.85) else { return false }
        let url = Paths.artwork.appendingPathComponent(id.uuidString + ".jpg")
        return (try? data.write(to: url)) != nil
    }

    // MARK: Songs
    func song(_ id: UUID) -> Song? { songs.first { $0.id == id } }
    var favorites: [Song] { songs.filter { $0.isFavorite } }

    func toggleFavorite(_ id: UUID) {
        guard let i = songs.firstIndex(where: { $0.id == id }) else { return }
        songs[i].isFavorite.toggle()
    }

    func delete(_ ids: [UUID]) {
        let set = Set(ids)
        for id in ids {
            guard let s = song(id) else { continue }
            try? FileManager.default.removeItem(at: s.url)
            try? FileManager.default.removeItem(at: Paths.artwork.appendingPathComponent(id.uuidString + ".jpg"))
        }
        songs.removeAll { set.contains($0.id) }
        for i in playlists.indices { playlists[i].songIDs.removeAll { set.contains($0) } }
        ids.forEach { onDelete?($0) }
    }

    // MARK: Playlists
    func songs(in playlist: Playlist) -> [Song] { playlist.songIDs.compactMap { song($0) } }

    func createPlaylist(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        playlists.append(Playlist(name: n.isEmpty ? "New Playlist" : n))
    }
    func rename(_ id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = n
    }
    func deletePlaylists(at offsets: IndexSet) { playlists.remove(atOffsets: offsets) }
    func deletePlaylist(_ id: UUID) { playlists.removeAll { $0.id == id } }

    func add(_ ids: [UUID], to playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        for id in ids where !playlists[i].songIDs.contains(id) { playlists[i].songIDs.append(id) }
    }
    func remove(_ songID: UUID, from playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].songIDs.removeAll { $0 == songID }
    }
    func removeSongs(at offsets: IndexSet, from playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].songIDs.remove(atOffsets: offsets)
    }
    func moveSongs(from: IndexSet, to: Int, in playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].songIDs.move(fromOffsets: from, toOffset: to)
    }
}
