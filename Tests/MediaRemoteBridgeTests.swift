import AppKit
import Foundation

@main
struct MediaRemoteBridgeTests {
    @MainActor static func main() {
        var checks = 0
        func expect(_ result: Bool, _ name: String) {
            checks += 1
            if !result { fputs("FAIL: \(name)\n", stderr); exit(1) }
        }
        let example: [String: Any] = [
            "kind": "snapshot", "available": true, "bundleID": "com.tencent.QQMusicMac",
            "title": "测试歌曲\n第二行", "artist": "歌手 A", "album": "专辑", "trackID": "123",
            "duration": 263.0, "position": 170.0, "playing": true
        ]
        let playing = MediaRemoteBridge.parseSnapshot(example)!
        expect(playing.source == .qqMusic, "QQ source preserved")
        expect(playing.track?.id == "qqMusic:123", "IDs namespaced by player")
        expect(playing.track?.title == "测试歌曲\n第二行", "Unicode and multiline text preserved")
        expect(playing.track?.artist == "歌手 A", "artist decoded")
        expect(playing.track?.album == "专辑", "album decoded")
        expect(playing.track?.duration == 263, "QQ duration in seconds")
        expect(playing.position == 170, "QQ elapsed time in seconds")
        expect(playing.playbackState == .playing, "playing callback controls state")
        var changed = example
        changed["playing"] = false
        changed["playbackRate"] = 1
        expect(MediaRemoteBridge.parseSnapshot(changed)?.playbackState == .paused, "stale playbackRate must not imply playing")
        var chromeExample = example
        chromeExample["bundleID"] = "com.google.Chrome"
        chromeExample["appName"] = "Google Chrome"
        let chromePlaying = MediaRemoteBridge.parseSnapshot(chromeExample)!
        expect(chromePlaying.source == .systemMedia, "Chrome maps to systemMedia")
        expect(chromePlaying.track?.customSourceName == "Google Chrome", "custom app name preserved")

        var appleExample = example
        appleExample["bundleID"] = "com.apple.Music"
        let applePlaying = MediaRemoteBridge.parseSnapshot(appleExample)!
        expect(applePlaying.source == .appleMusic, "Apple Music maps to appleMusic")

        var spotifyExample = example
        spotifyExample["bundleID"] = "com.spotify.client"
        let spotifyPlaying = MediaRemoteBridge.parseSnapshot(spotifyExample)!
        expect(spotifyPlaying.source == .spotify, "Spotify maps to spotify")

        changed = example; changed["bundleID"] = ""
        expect(MediaRemoteBridge.parseSnapshot(changed) == nil, "empty bundleID rejected")
        var neteaseExample = example
        neteaseExample["bundleID"] = "com.netease.163music"
        let neteasePlaying = MediaRemoteBridge.parseSnapshot(neteaseExample)!
        expect(neteasePlaying.source == .neteaseMusic, "NetEase source preserved")
        expect(neteasePlaying.track?.id == "neteaseMusic:123", "NetEase ID namespaced")
        expect(neteasePlaying.track?.title == "测试歌曲\n第二行", "NetEase title preserved")
        changed = example; changed["available"] = false
        expect(MediaRemoteBridge.parseSnapshot(changed) == nil, "inactive media has no stale card")
        expect(MediaRemoteBridge.parseSnapshot([:]) == nil, "empty metadata rejected")
        for title in ["", "  \n "] {
            changed = example; changed["title"] = title
            expect(MediaRemoteBridge.parseSnapshot(changed) == nil, "empty title rejected")
        }
        for (value, result) in [(Double.nan, 0.0), (Double.infinity, 0.0), (-10.0, 0.0), (500.0, 263.0)] {
            changed = example; changed["position"] = value
            expect(MediaRemoteBridge.parseSnapshot(changed)?.position == result, "invalid position bounded")
        }
        changed = example; changed["duration"] = -1.0
        expect(MediaRemoteBridge.parseSnapshot(changed)?.track?.duration == 0, "negative duration bounded")
        expect(MediaRemoteBridge.parseSnapshot(changed)?.position == 0, "position bounded by missing duration")
        changed = example; changed.removeValue(forKey: "trackID")
        expect(MediaRemoteBridge.parseSnapshot(changed)?.track?.id.contains("测试歌曲") == true, "deterministic fallback identity")
        changed = example; changed["artwork"] = Data([1, 2, 3]).base64EncodedString()
        expect(MediaRemoteBridge.parseSnapshot(changed)?.artworkData == Data([1, 2, 3]), "embedded cover decoded without network")
        changed["artwork"] = "invalid!"
        expect(MediaRemoteBridge.parseSnapshot(changed)?.artworkData == nil, "invalid cover discarded")
        expect(MediaRemoteCommand(rawValue: "launch") == nil, "unknown command rejected")
        expect(MediaRemoteCommand(rawValue: "toggle") != nil, "play toggle allowed")
        expect(MediaRemoteCommand(rawValue: "next") != nil, "next track allowed")
        expect(MediaRemoteCommand(rawValue: "previous") != nil, "previous track allowed")
        expect(QQMusicCommand(rawValue: "toggle") != nil, "legacy alias works")
        // Existing player parsing keeps its original duration conventions.
        let legacy = ["playing", "track", "歌曲", "歌手", "专辑", "263000", "170", "70", ""].joined(separator: "\u{001F}")
        expect(MusicService.parseMetadata(legacy, source: .spotify)?.track?.duration == 263, "Spotify milliseconds unchanged")
        let apple = legacy.replacingOccurrences(of: "263000", with: "263")
        expect(MusicService.parseMetadata(apple, source: .appleMusic)?.track?.duration == 263, "Apple Music seconds unchanged")
        changed = example; changed["playing"] = false; changed["position"] = 0.0; changed["positionAvailable"] = false
        let paused = MediaRemoteBridge.parseSnapshot(changed)!
        expect(!paused.hasPosition, "Media paused zero is unknown, not a reset")
        let preserved = MediaRemoteBridge.merge(paused, previous: playing)!
        expect(preserved.position == 170 && preserved.hasPosition, "pause retains last observed progress")
        expect(MediaRemoteBridge.merge(paused, previous: nil)?.hasPosition == false, "startup while paused does not invent progress")
        changed["trackID"] = "new-song"
        expect(MediaRemoteBridge.merge(MediaRemoteBridge.parseSnapshot(changed), previous: playing)?.hasPosition == false, "old song progress never transfers to a new song")
        expect(MediaRemoteBridge.merge(nil, previous: playing) == nil, "loss of media ownership clears previous metadata")
        print("PASS: \(checks) media remote checks")
    }
}
