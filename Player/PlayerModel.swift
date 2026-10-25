import SwiftUI
import AVFoundation
import MediaPlayer

enum RepeatMode { case off, all, one }

final class PlaybackClock: ObservableObject {
    @Published var time: Double = 0
}

struct EQPreset: Identifiable {
    let name: String
    let gains: [Float]
    var id: String { name }
}

enum NowPlayingArt {
    nonisolated static func make(_ img: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: img.size) { _ in img }
    }
}

@MainActor
final class PlayerModel: ObservableObject {
    static let frequencies: [Float] = [60, 150, 400, 1000, 2400, 6000, 12000, 16000]
    static let frequencyLabels = ["60", "150", "400", "1k", "2.4k", "6k", "12k", "16k"]
    static let presets: [EQPreset] = [
        EQPreset(name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Bass Boost", gains: [6, 5, 3, 1, 0, 0, 0, 0]),
        EQPreset(name: "Treble Boost", gains: [0, 0, 0, 0, 1, 3, 5, 6]),
        EQPreset(name: "Vocal", gains: [-2, -1, 0, 3, 4, 3, 1, 0]),
        EQPreset(name: "Rock", gains: [5, 3, -1, -2, 0, 3, 4, 5]),
        EQPreset(name: "Electronic", gains: [5, 4, 1, -1, -2, 1, 3, 4]),
        EQPreset(name: "Acoustic", gains: [3, 3, 2, 0, 1, 2, 3, 2]),
        EQPreset(name: "Loudness", gains: [5, 3, 0, 0, 0, 0, 2, 4])
    ]

    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var isShuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var eqEnabled: Bool {
        didSet { UserDefaults.standard.set(eqEnabled, forKey: "eqEnabled"); applyEQ() }
    }
    @Published private(set) var gains: [Float]

    let clock = PlaybackClock()

    private var original: [QueueItem] = []
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 8)
    private var file: AVAudioFile?
    private var lastFormat: AVAudioFormat?
    private var seekFrame: AVAudioFramePosition = 0
    private var generation = 0
    private var timer: Timer?

    var current: Song? { queue.indices.contains(index) ? queue[index].song : nil }
    var upNext: [QueueItem] {
        guard index + 1 < queue.count else { return [] }
        return Array(queue[(index + 1)...])
    }

    init() {
        let d = UserDefaults.standard
        eqEnabled = (d.object(forKey: "eqEnabled") as? Bool) ?? true
        let g = (d.array(forKey: "eqGains") as? [NSNumber])?.map { $0.floatValue } ?? []
        gains = g.count == 8 ? g : Array(repeating: 0, count: 8)
        setupEngine()
        setupRemote()
        observe()
    }

    // MARK: Engine
    private func setupEngine() {
        engine.attach(node)
        engine.attach(eq)
        for (i, band) in eq.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = Self.frequencies[i]
            band.bandwidth = 1.0
            band.bypass = false
        }
        applyEQ()
        engine.connect(node, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
    }

    private func reconnect(_ format: AVAudioFormat) {
        node.stop()
        if let last = lastFormat, last.isEqual(format) { return }
        engine.stop()
        engine.connect(node, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        engine.prepare()
        lastFormat = format
    }

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
    }

    // MARK: EQ
    private func applyEQ() {
        eq.bypass = !eqEnabled
        for (i, band) in eq.bands.enumerated() { band.gain = gains[i] }
        // simple anti-clipping headroom when boosting
        eq.globalGain = -max(0, gains.max() ?? 0) * 0.5
    }
    func setGain(_ band: Int, _ value: Float) {
        guard gains.indices.contains(band) else { return }
        gains[band] = value
        UserDefaults.standard.set(gains, forKey: "eqGains")
        applyEQ()
    }
    func setGains(_ values: [Float]) {
        guard values.count == 8 else { return }
        gains = values
        UserDefaults.standard.set(gains, forKey: "eqGains")
        applyEQ()
    }

    // MARK: Starting playback
    func play(_ songs: [Song], startingAt song: Song? = nil, shuffle: Bool? = nil) {
        guard !songs.isEmpty else { return }
        original = songs.map { QueueItem(song: $0) }
        if let s = shuffle { isShuffled = s }
        let start: QueueItem = song.flatMap { s in original.first { $0.song.id == s.id } }
            ?? (isShuffled ? original.randomElement()! : original[0])
        if isShuffled {
            queue = [start] + shuffledCopy(of: original.filter { $0.id != start.id })
        } else {
            queue = original
        }
        load(at: queue.firstIndex { $0.id == start.id } ?? 0, play: true)
    }

    private func load(at newIndex: Int, play: Bool, startAt: Double = 0) {
        guard queue.indices.contains(newIndex) else { stop(); return }
        index = newIndex
        let song = queue[newIndex].song
        guard let f = try? AVAudioFile(forReading: song.url) else {
            if newIndex + 1 < queue.count {
                load(at: newIndex + 1, play: play)
            } else {
                node.stop(); isPlaying = false; stopTimer()
            }
            return
        }
        file = f
        let sr = f.processingFormat.sampleRate
        duration = sr > 0 ? Double(f.length) / sr : song.duration
        reconnect(f.processingFormat)
        clock.time = startAt
        schedule(from: AVAudioFramePosition(startAt * sr))
        if play {
            startPlayback()
        } else {
            isPlaying = false
            stopTimer()
            updateNowPlaying()
        }
    }

    private func schedule(from frame: AVAudioFramePosition) {
        guard let f = file else { return }
        let total = f.length
        guard total > 0 else { return }
        let start = max(0, min(frame, total - 1))
        seekFrame = start
        generation += 1
        let gen = generation
        node.stop()
        node.scheduleSegment(f, startingFrame: start, frameCount: AVAudioFrameCount(total - start),
                             at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                self.trackFinished()
            }
        }
    }

    private func startPlayback() {
        configureSession()
        if !engine.isRunning {
            do { try engine.start() } catch { isPlaying = false; return }
        }
        node.play()
        isPlaying = true
        startTimer()
        updateNowPlaying()
    }

    // MARK: Transport
    func togglePlay() { isPlaying ? pause() : resume() }

    func pause() {
        guard isPlaying else { return }
        clock.time = computeTime()
        node.pause()
        isPlaying = false
        stopTimer()
        updateNowPlaying()
    }

    func resume() {
        guard current != nil, !isPlaying else { return }
        if !engine.isRunning {
            load(at: index, play: true, startAt: clock.time)
        } else {
            startPlayback()
        }
    }

    func seek(to t: Double) {
        guard let f = file else { return }
        let sr = f.processingFormat.sampleRate
        let target = max(0, min(t, max(duration - 0.1, 0)))
        let wasPlaying = isPlaying
        schedule(from: AVAudioFramePosition(target * sr))
        clock.time = target
        if wasPlaying { node.play() }
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count { load(at: index + 1, play: true) } else { wrap() }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if clock.time > 3 || index == 0 { seek(to: 0) } else { load(at: index - 1, play: true) }
    }

    private func wrap() {
        if isShuffled { queue = newCycleOrder() }
        load(at: 0, play: true)
    }

    private func trackFinished() {
        switch repeatMode {
        case .one:
            load(at: index, play: true)
        case .all:
            next()
        case .off:
            if index + 1 < queue.count { load(at: index + 1, play: true) }
            else { load(at: index, play: false) }
        }
    }

    func stop() {
        generation += 1
        node.stop()
        isPlaying = false
        stopTimer()
        queue = []
        original = []
        index = 0
        file = nil
        duration = 0
        clock.time = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: Shuffle
    func toggleShuffle() {
        isShuffled.toggle()
        guard queue.indices.contains(index) else { return }
        let currentItem = queue[index]
        if isShuffled {
            queue = [currentItem] + shuffledCopy(of: original.filter { $0.id != currentItem.id })
            index = 0
        } else {
            queue = original
            index = queue.firstIndex { $0.id == currentItem.id } ?? 0
        }
    }

    /// True shuffle (Fisher-Yates via shuffled()): every song appears once per cycle, and
    /// songs by the same artist are pulled apart so you don't get back-to-back repeats.
    private func shuffledCopy(of items: [QueueItem]) -> [QueueItem] {
        var a = items.shuffled()
        guard a.count > 2 else { return a }
        for i in 1..<a.count {
            guard a[i].song.artist == a[i - 1].song.artist, a[i].song.artist != "Unknown Artist" else { continue }
            var j = i + 1
            while j < a.count && a[j].song.artist == a[i].song.artist { j += 1 }
            if j < a.count { a.swapAt(i, j) }
        }
        return a
    }

    /// New order for the next pass: never starts with the song that just ended
    /// and never repeats the previous order.
    private func newCycleOrder() -> [QueueItem] {
        let lastID = queue.last?.id
        let oldIDs = queue.map { $0.id }
        var result = shuffledCopy(of: original)
        if original.count > 1 {
            var tries = 0
            while (result.first?.id == lastID || result.map { $0.id } == oldIDs) && tries < 12 {
                result = shuffledCopy(of: original)
                tries += 1
            }
        }
        return result
    }

    // MARK: Queue editing
    func playNext(_ song: Song) {
        guard queue.indices.contains(index) else { play([song]); return }
        let item = QueueItem(song: song)
        let currentID = queue[index].id
        queue.insert(item, at: index + 1)
        if let oi = original.firstIndex(where: { $0.id == currentID }) { original.insert(item, at: oi + 1) }
        else { original.append(item) }
    }

    func addToQueue(_ song: Song) {
        guard !queue.isEmpty else { play([song]); return }
        let item = QueueItem(song: song)
        queue.append(item)
        original.append(item)
    }

    func jump(to item: QueueItem) {
        if let i = queue.firstIndex(where: { $0.id == item.id }) { load(at: i, play: true) }
    }

    func removeUpNext(at offsets: IndexSet) {
        let base = index + 1
        let ids = offsets.map { queue[base + $0].id }
        queue.removeAll { ids.contains($0.id) }
        original.removeAll { ids.contains($0.id) }
    }

    func moveUpNext(from: IndexSet, to: Int) {
        var up = upNext
        up.move(fromOffsets: from, toOffset: to)
        queue = Array(queue[...index]) + up
        if !isShuffled { original = queue }
    }

    func removeSong(_ id: UUID) {
        guard queue.indices.contains(index) else { return }
        if queue[index].song.id == id { stop(); return }
        let currentID = queue[index].id
        queue.removeAll { $0.song.id == id }
        original.removeAll { $0.song.id == id }
        index = queue.firstIndex { $0.id == currentID } ?? 0
    }

    // MARK: Time
    private func computeTime() -> Double {
        guard let f = file else { return 0 }
        let sr = f.processingFormat.sampleRate
        if node.isPlaying, let nt = node.lastRenderTime, let pt = node.playerTime(forNodeTime: nt), sr > 0 {
            return max(0, min((Double(seekFrame) + Double(pt.sampleTime)) / sr, duration))
        }
        return clock.time
    }

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
    private func tick() { if isPlaying { clock.time = computeTime() } }

    // MARK: System integration
    private func updateNowPlaying() {
        guard let s = current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: s.title,
            MPMediaItemPropertyArtist: s.artist,
            MPMediaItemPropertyAlbumTitle: s.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clock.time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let img = ArtworkCache.image(for: s) { info[MPMediaItemPropertyArtwork] = NowPlayingArt.make(img) }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        c.changePlaybackPositionCommand.isEnabled = true
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                let t = e.positionTime
                Task { @MainActor in self?.seek(to: t) }
            }
            return .success
        }
    }

    private func observe() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let t = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let o = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            Task { @MainActor in self?.handleInterruption(typeRaw: t, optionsRaw: o) }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let r = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            Task { @MainActor in self?.handleRouteChange(reasonRaw: r) }
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleConfigChange() }
        }
    }

    private func handleInterruption(typeRaw: UInt, optionsRaw: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        if type == .began {
            pause()
        } else if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
            resume()
        }
    }

    private func handleRouteChange(reasonRaw: UInt) {
        if AVAudioSession.RouteChangeReason(rawValue: reasonRaw) == .oldDeviceUnavailable { pause() }
    }

    private func handleConfigChange() {
        guard file != nil, current != nil else { return }
        load(at: index, play: isPlaying, startAt: clock.time)
    }
}
