import Foundation
import Testing
@testable import MacBookIsland

@Test("AX 临时失去封面时仅复用同进程同曲的已验证封面")
func qishuiArtworkFallbackRequiresVerifiedIdentity() {
    let data = Data([1, 2, 3])
    let mediaTrack = MediaRemoteNowPlayingTrack(title: "Song", artist: "A, B", album: nil, artworkData: data, isPlaying: true, progress: 0.2, elapsedTime: 20, duration: 100, sourceBundleIdentifier: "com.soda.music", sourceProcessIdentifier: 42, sourceName: "test")
    let snapshot = MediaRemoteNowPlayingSnapshot(isAvailable: true, isVerifiedQishuiSource: true, currentTrack: mediaTrack, diagnostic: "", checkedAt: Date())
    #expect(QishuiArtworkFallbackPolicy.artwork(from: snapshot, for: .init(processIdentifier: 42, title: "Song", artist: "A / B")) == data)
    #expect(QishuiArtworkFallbackPolicy.artwork(from: snapshot, for: .init(processIdentifier: 43, title: "Song", artist: "A, B")) == nil)
    #expect(QishuiArtworkFallbackPolicy.artwork(from: snapshot, for: .init(processIdentifier: 42, title: "Other", artist: "A, B")) == nil)
    let unverified = MediaRemoteNowPlayingSnapshot(isAvailable: true, isVerifiedQishuiSource: false, currentTrack: mediaTrack, diagnostic: "", checkedAt: Date())
    #expect(QishuiArtworkFallbackPolicy.artwork(from: unverified, for: .init(processIdentifier: 42, title: "Song", artist: "A, B")) == nil)
    #expect(QishuiArtworkFallbackPolicy.artwork(from: snapshot, for: nil) == nil)
}
