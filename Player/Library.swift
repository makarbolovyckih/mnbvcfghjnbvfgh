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

    static func storedSongs() -> [Song] {
        let loaded: [Song] = Library.load("songs.json") ?? []
        return loaded.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    /// Re-reads tags/artwork for songs that were imported before metadata reading worked.
    func refreshMetadata(force: Bool = false) {
        Task {
            for song in songs where force || !song.hasArtwork || song.artist == "Unknown Artist" || song.album == "Unknown Album" {
                let meta = await MetadataReader.read(url: song.url)
                guard let i = songs.firstIndex(where: { $0.id == song.id }) else { continue }
                var s = songs[i]
                let wasUntagged = s.artist == "Unknown Artist"
                if let a = meta.artist { s.artist = a }
                if let a = meta.album { s.album = a }
                if wasUntagged, let t = meta.title { s.title = t }
                if !s.hasArtwork, let data = meta.artwork, let img = UIImage(data: data) {
                    s.hasArtwork = saveArtwork(img, id: s.id)
                }
                if s != songs[i] { songs[i] = s }
            }
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

        let meta = await MetadataReader.read(url: dest)
        let fallbackName = source.deletingPathExtension().lastPathComponent
        var title = meta.title ?? fallbackName
        var artist = meta.artist ?? "Unknown Artist"
        let album = meta.album ?? "Unknown Album"
        // No tags at all: try "Artist - Title" from the file name
        if meta.title == nil && meta.artist == nil, let r = fallbackName.range(of: " - ") {
            let a = fallbackName[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            let t = fallbackName[r.upperBound...].trimmingCharacters(in: .whitespaces)
            if !a.isEmpty && !t.isEmpty { artist = a; title = t }
        }
        var hasArt = false
        if let data = meta.artwork, let img = UIImage(data: data) { hasArt = saveArtwork(img, id: id) }
        let duration = meta.duration
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

struct SongMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var artwork: Data?
    var duration: Double = 0
}

enum MetadataReader {
    /// Reads tags from every metadata format in the file (ID3, iTunes/MP4, QuickTime...).
    /// Items in `commonMetadata` keep their format-specific identifier, so matching on
    /// `commonIdentifier*` never worked; we match on the common key plus known raw identifiers.
    static func read(url: URL) async -> SongMetadata {
        let asset = AVURLAsset(url: url)
        var meta = SongMetadata()
        if let d = try? await asset.load(.duration), d.seconds.isFinite { meta.duration = d.seconds }

        var items: [AVMetadataItem] = []
        if let common = try? await asset.load(.commonMetadata) { items += common }
        if let all = try? await asset.load(.metadata) { items += all }
        if let formats = try? await asset.load(.availableMetadataFormats) {
            for f in formats {
                if let more = try? await asset.loadMetadata(for: f) { items += more }
            }
        }

        let metaItems = items
        func matches(_ item: AVMetadataItem, key: AVMetadataKey, ids: [String]) -> Bool {
            if item.commonKey == key { return true }
            guard let raw = item.identifier?.rawValue else { return false }
            return ids.contains(raw)
        }
        func firstString(key: AVMetadataKey, ids: [String]) async -> String? {
            for item in metaItems where matches(item, key: key, ids: ids) {
                if let v = try? await item.load(.stringValue) {
                    let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { return t }
                }
            }
            return nil
        }

        meta.title = await firstString(key: .commonKeyTitle, ids: ["id3/TIT2", "itsk/\u{A9}nam", "common/title"])
        meta.artist = await firstString(key: .commonKeyArtist, ids: ["id3/TPE1", "id3/TPE2", "itsk/\u{A9}ART", "itsk/aART", "common/artist"])
        meta.album = await firstString(key: .commonKeyAlbumName, ids: ["id3/TALB", "itsk/\u{A9}alb", "common/albumName"])

        for item in metaItems where matches(item, key: .commonKeyArtwork, ids: ["id3/APIC", "itsk/covr", "common/artwork"]) {
            if let d = try? await item.load(.dataValue), !d.isEmpty { meta.artwork = d; break }
            if let v = try? await item.load(.value) {
                if let d = v as? Data, !d.isEmpty { meta.artwork = d; break }
                if let dict = v as? [AnyHashable: Any], let d = dict["data"] as? Data, !d.isEmpty { meta.artwork = d; break }
            }
        }
        return meta
    }
}
