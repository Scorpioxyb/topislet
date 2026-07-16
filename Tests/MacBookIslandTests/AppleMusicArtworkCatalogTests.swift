import Foundation
import Testing
@testable import MacBookIsland

@Test("Apple Music 电台曲目可精确匹配目录封面")
func appleMusicRadioTrackMatchesCatalogArtwork() throws {
    let observation = try #require(AppleMusicObservation.decode(fields: [
        "4E42523FD3FD7A00",
        "Bruce Wayne",
        "YoungBoy Never Broke Again",
        "Slime Cry",
        "176.3",
        "64.8",
        "playing"
    ]))
    let searchData = Data(#"""
    {
      "results": [
        {
          "trackName": "Bruce Wayne",
          "artistName": "YoungBoy Never Broke Again",
          "collectionName": "Slime Cry",
          "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/example/100x100bb.jpg"
        },
        {
          "trackName": "Bruce Wayne",
          "artistName": "Another Artist",
          "collectionName": "Other Album",
          "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/wrong/100x100bb.jpg"
        }
      ]
    }
    """#.utf8)

    let artworkURL = try #require(
        AppleMusicCatalogArtworkResolver.artworkURL(
            from: searchData,
            matching: observation
        )
    )
    #expect(artworkURL.absoluteString.contains("/example/600x600bb.jpg"))
}

@Test("Apple Music 目录不会用同名异歌手封面")
func appleMusicCatalogRejectsWrongArtist() throws {
    let observation = try #require(AppleMusicObservation.decode(fields: [
        "ABC",
        "Home",
        "Artist A",
        "Album A",
        "180",
        "10",
        "playing"
    ]))
    let searchData = Data(#"""
    {
      "results": [
        {
          "trackName": "Home",
          "artistName": "Artist B",
          "collectionName": "Album B",
          "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/wrong/100x100bb.jpg"
        }
      ]
    }
    """#.utf8)

    #expect(AppleMusicCatalogArtworkResolver.artworkURL(
        from: searchData,
        matching: observation
    ) == nil)
}

@Test("Apple Music 目录拒绝专辑不符或多重歧义")
func appleMusicCatalogRejectsAlbumMismatchAndAmbiguity() throws {
    let observation = try #require(AppleMusicObservation.decode(fields: [
        "ABC",
        "Home",
        "Artist A",
        "Album A",
        "180",
        "10",
        "playing"
    ]))
    let mismatchData = Data(#"""
    {
      "results": [
        {
          "trackName": "Home",
          "artistName": "Artist A",
          "collectionName": "Album B",
          "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/a/100x100bb.jpg"
        }
      ]
    }
    """#.utf8)
    #expect(AppleMusicCatalogArtworkResolver.artworkURL(
        from: mismatchData,
        matching: observation
    ) == nil)

    let ambiguousData = Data(#"""
    {
      "results": [
        {
          "trackName": "Home",
          "artistName": "Artist A",
          "collectionName": "Album A",
          "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/a/100x100bb.jpg"
        },
        {
          "trackName": "Home",
          "artistName": "Artist A",
          "collectionName": "Album A",
          "artworkUrl100": "https://is2-ssl.mzstatic.com/image/thumb/b/100x100bb.jpg"
        }
      ]
    }
    """#.utf8)
    #expect(AppleMusicCatalogArtworkResolver.artworkURL(
        from: ambiguousData,
        matching: observation
    ) == nil)
}

@Test("Apple Music 目录查询绑定地区和歌曲身份")
func appleMusicCatalogSearchURLUsesTrackIdentity() throws {
    let url = try #require(AppleMusicCatalogArtworkResolver.searchURL(
        title: "Janice STFU",
        artist: "Drake",
        countryCode: "cn"
    ))
    let components = try #require(URLComponents(
        url: url,
        resolvingAgainstBaseURL: false
    ))
    let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
        ($0.name, $0.value ?? "")
    })

    #expect(values["term"] == "Drake Janice STFU")
    #expect(values["entity"] == "song")
    #expect(values["country"] == "CN")
}

@Test("Apple Music 封面网络仅允许 Apple HTTPS 主机")
func appleMusicArtworkNetworkAllowlistIsClosed() throws {
    #expect(AppleMusicCatalogArtworkResolver.isAllowedNetworkURL(
        try #require(URL(string: "https://itunes.apple.com/search"))
    ))
    #expect(AppleMusicCatalogArtworkResolver.isAllowedNetworkURL(
        try #require(URL(string: "https://is1-ssl.mzstatic.com/image.jpg"))
    ))
    #expect(!AppleMusicCatalogArtworkResolver.isAllowedNetworkURL(
        try #require(URL(string: "http://itunes.apple.com/search"))
    ))
    #expect(!AppleMusicCatalogArtworkResolver.isAllowedNetworkURL(
        try #require(URL(string: "https://itunes.apple.com.evil.example/search"))
    ))
    #expect(!AppleMusicCatalogArtworkResolver.isAllowedNetworkURL(
        try #require(URL(string: "https://127.0.0.1/image.jpg"))
    ))
}
