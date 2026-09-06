# Music library

Fittr assigns **local Music app tracks** to exercises, not Apple Music catalog streams.

`MusicService` uses `MPMediaLibrary` and `MPMusicPlayerController.systemMusicPlayer`.

You can:

- Browse playlists already on the iPhone
- Search the on-device library by title, artist, or album
- Play the chosen MP3 / library song when an exercise starts (if auto-play is on)

Assignments store the Media Player **persistent ID** plus cached title/artist. Nothing is bundled.

Allow library access from Settings → Workout music, or the first time you pick a track. The workout logger works without this permission.

Tracks must already be in the iPhone Music app (synced MP3s, ripped CDs, or downloaded library songs).
