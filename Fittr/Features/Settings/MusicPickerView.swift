import SwiftData
import SwiftUI

struct MusicPickerView: View {
    var exerciseId: UUID?
    var template: WorkoutTemplate?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var assignments: [MusicAssignment]

    @State private var tab: Tab = .playlists
    @State private var query = ""
    @State private var results: [MusicTrackInfo] = []
    @State private var playlists: [MusicPlaylistInfo] = []
    @State private var selectedPlaylist: MusicPlaylistInfo?
    @State private var playlistTracks: [MusicTrackInfo] = []
    @State private var status = "Fittr uses songs already on this iPhone — local playlists and MP3s in the Music app."
    @State private var isLoading = false

    private enum Tab: String, CaseIterable, Identifiable {
        case playlists = "Playlists"
        case search = "Search"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Source", selection: $tab) {
                        ForEach(Tab.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch tab {
                case .playlists:
                    playlistContent
                case .search:
                    searchContent
                }
            }
            .navigationTitle("Assign local track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadPlaylists() }
            .onChange(of: tab) { _, newTab in
                if newTab == .playlists {
                    selectedPlaylist = nil
                    playlistTracks = []
                }
            }
        }
    }
}

private extension MusicPickerView {
    @ViewBuilder
    var playlistContent: some View {
        if let selectedPlaylist {
            Section(selectedPlaylist.name) {
                Button("All playlists") {
                    self.selectedPlaylist = nil
                    playlistTracks = []
                }
                if playlistTracks.isEmpty {
                    Text("This playlist has no songs Fittr can see on the phone.")
                        .foregroundStyle(.secondary)
                } else {
                    playlistButton(selectedPlaylist)
                    ForEach(playlistTracks) { track in
                        trackButton(track)
                    }
                }
            }
        } else if playlists.isEmpty {
            Text(isLoading ? "Loading playlists…" : "No local playlists found. Create one in the Music app, or search your library.")
                .foregroundStyle(.secondary)
        } else {
            Section("Playlists on this iPhone") {
                ForEach(playlists) { playlist in
                    Button {
                        Task { await openPlaylist(playlist) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(playlist.name)
                                    .foregroundStyle(.primary)
                                Text("\(playlist.trackCount) songs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    var searchContent: some View {
        Section {
            TextField("Title or artist", text: $query)
                .textInputAutocapitalization(.never)
                .onSubmit { Task { await search() } }
            Button("Search library") {
                Task { await search() }
            }
        }
        Section("Matches") {
            if results.isEmpty {
                Text("Search looks through the Music library on this iPhone, including synced MP3s.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results) { track in
                    trackButton(track)
                }
            }
        }
    }

    /// Assigning the whole playlist rather than one song from it. A single track
    /// runs out long before a 35-minute ride does.
    func playlistButton(_ playlist: MusicPlaylistInfo) -> some View {
        Button {
            assign(playlist)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "music.note.list")
                    .foregroundStyle(FittrTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Play the whole playlist")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(playlistTracks.count) songs, repeating — lasts the session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    func trackButton(_ track: MusicTrackInfo) -> some View {
        Button {
            assign(track)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !track.album.isEmpty {
                    Text(track.album)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    func loadPlaylists() async {
        isLoading = true
        let music = FittrDependencies.shared.music
        let granted = await music.requestAuthorization()
        guard granted else {
            status = "Music library access was not granted. Fittr can still log workouts without music."
            isLoading = false
            return
        }
        playlists = await music.localPlaylists()
        status = playlists.isEmpty
            ? "No playlists on this iPhone yet. Search by title or artist instead."
            : "Choose a playlist song, or search the local library."
        isLoading = false
    }

    func openPlaylist(_ playlist: MusicPlaylistInfo) async {
        selectedPlaylist = playlist
        playlistTracks = await FittrDependencies.shared.music.songsInPlaylist(id: playlist.id)
        status = "\(playlist.name) · \(playlistTracks.count) songs"
    }

    func search() async {
        let music = FittrDependencies.shared.music
        let granted = await music.requestAuthorization()
        guard granted else {
            status = "Music library access was not granted."
            return
        }
        results = await music.searchSongs(query)
        status = results.isEmpty ? "No local matches for “\(query)”." : "\(results.count) local tracks"
    }

    func assign(_ track: MusicTrackInfo) {
        insert(
            MusicAssignment(
                scope: exerciseId == nil ? .workout : .exercise,
                musicItemID: track.id,
                cachedTitle: track.title,
                cachedArtist: track.artist,
                source: .localLibrary,
                template: template,
                exerciseId: exerciseId
            )
        )
    }

    func assign(_ playlist: MusicPlaylistInfo) {
        // The first track doubles as the fallback if the playlist is later emptied
        // or deleted in the Music app, so the assignment still plays something.
        let first = playlistTracks.first
        insert(
            MusicAssignment(
                scope: exerciseId == nil ? .workout : .exercise,
                musicItemID: first?.id ?? "",
                cachedTitle: playlist.name,
                cachedArtist: "\(playlistTracks.count) songs",
                source: .localLibrary,
                playlistID: playlist.id,
                playlistName: playlist.name,
                template: template,
                exerciseId: exerciseId
            )
        )
    }

    func insert(_ assignment: MusicAssignment) {
        for existing in assignments where shouldReplace(existing) {
            modelContext.delete(existing)
        }
        modelContext.insert(assignment)
        try? modelContext.save()
        dismiss()
    }

    func shouldReplace(_ existing: MusicAssignment) -> Bool {
        if let exerciseId {
            return existing.exerciseId == exerciseId
        }
        if let template {
            return existing.template?.id == template.id && existing.scope == .workout
        }
        return false
    }
}
