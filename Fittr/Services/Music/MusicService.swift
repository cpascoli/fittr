import Foundation
import MediaPlayer

struct MusicTrackInfo: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var artist: String
    var artworkURL: URL?
    var album: String = ""
}

struct MusicPlaylistInfo: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var trackCount: Int
}

enum MusicItemSource: String, Codable {
    case localLibrary
    case catalog
}

@MainActor
protocol MusicServicing: AnyObject {
    var isAuthorized: Bool { get }
    var nowPlaying: MusicTrackInfo? { get }
    var isPlaying: Bool { get }
    func requestAuthorization() async -> Bool
    func searchSongs(_ query: String) async -> [MusicTrackInfo]
    func localPlaylists() async -> [MusicPlaylistInfo]
    func songsInPlaylist(id: String) async -> [MusicTrackInfo]
    func play(itemID: String, restart: Bool) async
    /// Queues a whole list so playback outlasts one song. `restart` reloads the
    /// queue from the top; otherwise an unchanged queue is resumed where it was.
    func play(itemIDs: [String], restart: Bool, shuffle: Bool, repeatAll: Bool) async
    func preview(itemID: String, seconds: TimeInterval) async
    func playPause()
    func pause()
    func resume()
    func stop()
    func next()
    func previous()
}

@MainActor
final class MusicService: MusicServicing {
    private(set) var isAuthorized = false
    private(set) var nowPlaying: MusicTrackInfo?
    private var pausedAt: TimeInterval?
    private var holdQueue = false
    /// What Fittr last put in the queue, in order, so a repeat request can tell
    /// "already playing this" from "needs a new queue".
    private var queuedItemIDs: [UInt64] = []

    var isPlaying: Bool {
        MPMusicPlayerController.systemMusicPlayer.playbackState == .playing
    }

    func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { result in
                continuation.resume(returning: result)
            }
        }
        isAuthorized = status == .authorized
        return isAuthorized
    }

    func searchSongs(_ query: String) async -> [MusicTrackInfo] {
        guard await ensureAuthorized() else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let items = MPMediaQuery.songs().items ?? []
        return items
            .filter { Self.matches($0, query: trimmed) }
            .prefix(80)
            .map(Self.track(from:))
    }

    func localPlaylists() async -> [MusicPlaylistInfo] {
        guard await ensureAuthorized() else { return [] }
        return (MPMediaQuery.playlists().collections ?? []).compactMap { collection in
            guard let playlist = collection as? MPMediaPlaylist else { return nil }
            let name = playlist.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }
            return MusicPlaylistInfo(
                id: String(playlist.persistentID),
                name: name,
                trackCount: playlist.items.count
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func songsInPlaylist(id: String) async -> [MusicTrackInfo] {
        guard await ensureAuthorized(), let persistentID = UInt64(id) else { return [] }
        let query = MPMediaQuery.playlists()
        query.addFilterPredicate(
            MPMediaPropertyPredicate(
                value: persistentID,
                forProperty: MPMediaPlaylistPropertyPersistentID
            )
        )
        return (query.collections?.first?.items ?? []).map(Self.track(from:))
    }

    func play(itemID: String, restart: Bool) async {
        await play(itemIDs: [itemID], restart: restart, shuffle: false, repeatAll: false)
    }

    func play(itemIDs: [String], restart: Bool, shuffle: Bool, repeatAll: Bool) async {
        guard await ensureAuthorized() else { return }
        let persistentIDs = itemIDs.compactMap(UInt64.init)
        guard !persistentIDs.isEmpty else { return }
        let items = Self.mediaItems(for: persistentIDs)
        guard !items.isEmpty else { return }

        let systemPlayer = MPMusicPlayerController.systemMusicPlayer
        // Queue identity, not just the current song. Asking "is the right track
        // playing?" cannot distinguish a one-song queue from the same song sitting
        // inside a playlist, and getting that wrong strands playback after one track.
        let requested = items.map(\.persistentID)
        let sameQueue = queuedItemIDs == requested

        if restart || !sameQueue {
            holdQueue = false
            pausedAt = nil
            systemPlayer.setQueue(with: MPMediaItemCollection(items: items))
            queuedItemIDs = requested
            systemPlayer.shuffleMode = shuffle ? .songs : .off
            systemPlayer.repeatMode = repeatAll ? .all : .none
            // `setQueue` is asynchronous. Calling `play()` or setting
            // `currentPlaybackTime` before the queue has actually loaded applies
            // them to the outgoing queue, which is how a new exercise ended up
            // restarting the previous exercise's song.
            await prepareToPlay(systemPlayer)
            systemPlayer.play()
            if restart {
                systemPlayer.currentPlaybackTime = 0
            }
            updateNowPlaying(fallback: items[0])
            return
        }

        if holdQueue {
            resume()
        } else {
            systemPlayer.play()
        }
        updateNowPlaying(fallback: items[0])
    }

    private func prepareToPlay(_ player: MPMusicPlayerController) async {
        await withCheckedContinuation { continuation in
            player.prepareToPlay { _ in
                continuation.resume()
            }
        }
    }

    /// Reports what the player says is playing, falling back to the request only
    /// when it has not caught up yet. Reporting the request as though it were the
    /// outcome is what hid the queue bug: the UI named the right song throughout.
    private func updateNowPlaying(fallback: MPMediaItem) {
        let item = MPMusicPlayerController.systemMusicPlayer.nowPlayingItem ?? fallback
        nowPlaying = Self.track(from: item)
    }

    /// One query for the whole list. Filtering the song library per ID turns a
    /// 40-track playlist into 40 full-library scans.
    private static func mediaItems(for persistentIDs: [UInt64]) -> [MPMediaItem] {
        let wanted = Set(persistentIDs)
        let byID = Dictionary(
            (MPMediaQuery.songs().items ?? [])
                .filter { wanted.contains($0.persistentID) }
                .map { ($0.persistentID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return persistentIDs.compactMap { byID[$0] }
    }

    func preview(itemID: String, seconds: TimeInterval) async {
        await play(itemID: itemID, restart: true)
        try? await Task.sleep(for: .seconds(seconds))
        MPMusicPlayerController.systemMusicPlayer.pause()
    }

    func playPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        let systemPlayer = MPMusicPlayerController.systemMusicPlayer
        pausedAt = Self.sanitizedTime(systemPlayer.currentPlaybackTime)
        holdQueue = true
        systemPlayer.pause()
    }

    func resume() {
        holdQueue = false
        let systemPlayer = MPMusicPlayerController.systemMusicPlayer
        let time = pausedAt
        systemPlayer.play()
        restorePlaybackTime(time, on: systemPlayer)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            restorePlaybackTime(time, on: systemPlayer)
        }
    }

    func stop() {
        let systemPlayer = MPMusicPlayerController.systemMusicPlayer
        holdQueue = false
        pausedAt = nil
        queuedItemIDs = []
        systemPlayer.stop()
        nowPlaying = nil
    }

    func next() {
        MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
    }

    func previous() {
        MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem()
    }

    private func restorePlaybackTime(_ time: TimeInterval?, on player: MPMusicPlayerController) {
        guard let time, time.isFinite, time >= 0 else { return }
        player.currentPlaybackTime = time
    }

    private static func sanitizedTime(_ time: TimeInterval) -> TimeInterval? {
        guard time.isFinite, time >= 0 else { return nil }
        return time
    }

    private func ensureAuthorized() async -> Bool {
        if isAuthorized { return true }
        return await requestAuthorization()
    }

    private static func matches(_ item: MPMediaItem, query: String) -> Bool {
        let title = item.title ?? ""
        let artist = item.artist ?? ""
        let album = item.albumTitle ?? ""
        return title.localizedCaseInsensitiveContains(query)
            || artist.localizedCaseInsensitiveContains(query)
            || album.localizedCaseInsensitiveContains(query)
    }

    private static func track(from item: MPMediaItem) -> MusicTrackInfo {
        MusicTrackInfo(
            id: String(item.persistentID),
            title: item.title ?? "Unknown title",
            artist: item.artist ?? "Unknown artist",
            artworkURL: nil,
            album: item.albumTitle ?? ""
        )
    }
}

@MainActor
final class MockMusicService: MusicServicing {
    var isAuthorized = false
    var nowPlaying: MusicTrackInfo?
    var isPlaying = false
    var catalog: [MusicTrackInfo] = []
    var playlists: [MusicPlaylistInfo] = []
    var playlistSongs: [String: [MusicTrackInfo]] = [:]
    var playedIDs: [String] = []
    var queuedIDs: [String] = []
    var didShuffle = false
    var didRepeat = false

    func requestAuthorization() async -> Bool {
        isAuthorized = true
        return true
    }

    func searchSongs(_ query: String) async -> [MusicTrackInfo] {
        catalog.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query)
        }
    }

    func localPlaylists() async -> [MusicPlaylistInfo] { playlists }

    func songsInPlaylist(id: String) async -> [MusicTrackInfo] {
        playlistSongs[id] ?? []
    }

    func play(itemID: String, restart: Bool) async {
        await play(itemIDs: [itemID], restart: restart, shuffle: false, repeatAll: false)
    }

    func play(itemIDs: [String], restart: Bool, shuffle: Bool, repeatAll: Bool) async {
        guard let first = itemIDs.first else { return }
        playedIDs.append(first)
        queuedIDs = itemIDs
        didShuffle = shuffle
        didRepeat = repeatAll
        nowPlaying = catalog.first { $0.id == first }
        isPlaying = true
    }

    func preview(itemID: String, seconds: TimeInterval) async {
        await play(itemID: itemID, restart: true)
        isPlaying = false
    }

    func playPause() { isPlaying.toggle() }

    func pause() { isPlaying = false }

    func resume() { isPlaying = true }

    func stop() {
        isPlaying = false
        nowPlaying = nil
    }

    func next() {}
    func previous() {}
}
