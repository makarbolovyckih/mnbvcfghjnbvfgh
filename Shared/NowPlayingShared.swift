import Foundation
import UIKit

/// What the widget needs to draw itself. Written by the app, read by the widget.
struct NowPlayingSnapshot: Codable, Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var songID: String
    var hasArtwork: Bool
}

enum SharedStore {
    static let defaultGroup = "group.com.example.player"

    /// App group container. Sideloading tools may rewrite the group id, so we also look
    /// at the ids listed in Info.plist before falling back to the default.
    static var containerURL: URL? {
        var ids = (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]) ?? []
        ids.append(defaultGroup)
        for id in ids {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return url }
        }
        return nil
    }

    private static var snapshotURL: URL? { containerURL?.appendingPathComponent("nowplaying.json") }
    private static var artworkURL: URL? { containerURL?.appendingPathComponent("nowplaying-art.jpg") }

    static func readSnapshot() -> NowPlayingSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
    }

    static func readArtwork() -> UIImage? {
        guard let url = artworkURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func write(_ snapshot: NowPlayingSnapshot?, artwork: UIImage?, updateArtwork: Bool) {
        guard let sURL = snapshotURL, let aURL = artworkURL else { return }
        guard let snapshot else {
            try? FileManager.default.removeItem(at: sURL)
            try? FileManager.default.removeItem(at: aURL)
            return
        }
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: sURL, options: .atomic) }
        guard updateArtwork else { return }
        if let artwork, let data = downscaled(artwork, maxSide: 360).jpegData(compressionQuality: 0.8) {
            try? data.write(to: aURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: aURL)
        }
    }

    private static func downscaled(_ img: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        if scale >= 1 { return img }
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
