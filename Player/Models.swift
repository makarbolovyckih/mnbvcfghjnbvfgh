import SwiftUI

enum Paths {
    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static let support: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Player", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static let songs: URL = sub("Songs")
    static let artwork: URL = sub("Artwork")
    private static func sub(_ name: String) -> URL {
        let u = support.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

struct Song: Identifiable, Codable, Hashable {
    var id = UUID()
    var fileName: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var hasArtwork: Bool
    var isFavorite = false
    var dateAdded = Date()
    var url: URL { Paths.songs.appendingPathComponent(fileName) }
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var songIDs: [UUID] = []
}

struct QueueItem: Identifiable, Hashable {
    let id = UUID()
    let song: Song
}

enum SortOrder: String, CaseIterable, Identifiable {
    case title = "Title", artist = "Artist", recent = "Recently Added"
    var id: String { rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case red, pink, orange, yellow, green, teal, blue, indigo, purple
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .red: return .red
        case .pink: return .pink
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        }
    }
}

struct IconOption: Identifiable {
    let id: String          // alternate icon name, "" = default
    let name: String
    let colors: [Color]
    var altName: String? { id.isEmpty ? nil : id }

    static let all: [IconOption] = [
        IconOption(id: "", name: "Red", colors: [Color(red: 1, green: 0.37, blue: 0.43), Color(red: 0.84, green: 0.08, blue: 0.24)]),
        IconOption(id: "IconBlue", name: "Blue", colors: [Color(red: 0.31, green: 0.67, blue: 1), Color(red: 0.11, green: 0.31, blue: 0.85)]),
        IconOption(id: "IconPurple", name: "Purple", colors: [Color(red: 0.75, green: 0.52, blue: 0.99), Color(red: 0.43, green: 0.16, blue: 0.85)]),
        IconOption(id: "IconGreen", name: "Green", colors: [Color(red: 0.29, green: 0.87, blue: 0.5), Color(red: 0.08, green: 0.5, blue: 0.24)]),
        IconOption(id: "IconOrange", name: "Orange", colors: [Color(red: 0.99, green: 0.73, blue: 0.45), Color(red: 0.92, green: 0.35, blue: 0.05)]),
        IconOption(id: "IconBlack", name: "Black", colors: [Color(red: 0.23, green: 0.23, blue: 0.24), .black])
    ]
}

private struct AccentKey: EnvironmentKey { static let defaultValue: Color = .red }
extension EnvironmentValues {
    var accent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

func timeString(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds)
    return String(format: "%d:%02d", s / 60, s % 60)
}

enum ArtworkCache {
    static let cache = NSCache<NSString, UIImage>()
    static func image(for song: Song) -> UIImage? {
        guard song.hasArtwork else { return nil }
        let key = song.id.uuidString as NSString
        if let i = cache.object(forKey: key) { return i }
        let url = Paths.artwork.appendingPathComponent(song.id.uuidString + ".jpg")
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
}
