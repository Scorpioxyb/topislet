import AppKit
import Foundation
import ImageIO

enum AppleMusicCatalogArtworkResult: Sendable {
    case success(Data)
    case notFound
    case transientFailure
}

private final class AppleMusicArtworkRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        _ = session
        _ = task
        _ = response
        guard let url = request.url,
              AppleMusicCatalogArtworkResolver.isAllowedNetworkURL(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private enum AppleMusicArtworkNetwork {
    static let redirectDelegate = AppleMusicArtworkRedirectDelegate()
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 0,
            diskPath: nil
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
    }()
}

struct AppleMusicCatalogArtworkResolver: Sendable {
    private struct SearchResponse: Decodable {
        let results: [SearchResult]
    }

    private struct SearchResult: Decodable {
        let trackName: String
        let artistName: String
        let collectionName: String?
        let artworkUrl100: URL?
    }

    private static let maximumSearchResponseBytes = 1 * 1024 * 1024
    private static let maximumArtworkBytes = 8 * 1024 * 1024
    private static let maximumArtworkPixels = 8192.0

    let session: URLSession
    let countryCode: String?

    init(
        session: URLSession? = nil,
        countryCode: String? = Locale.current.region?.identifier
    ) {
        self.session = session ?? AppleMusicArtworkNetwork.session
        self.countryCode = countryCode
    }

    func artworkData(
        for observation: AppleMusicObservation
    ) async -> AppleMusicCatalogArtworkResult {
        guard let title = observation.title,
              !title.isEmpty else { return .notFound }

        var hadTransientFailure = false
        var searches: [String?] = []
        if let countryCode {
            searches.append(countryCode)
        }
        searches.append(nil)
        var artworkURL: URL?
        for region in searches {
            let searchResult = await searchArtworkURL(
                at: Self.searchURL(
                    title: title,
                    artist: observation.artist,
                    countryCode: region
                ),
                matching: observation
            )
            switch searchResult {
            case let .success(url):
                artworkURL = url
            case .notFound:
                break
            case .transientFailure:
                hadTransientFailure = true
            }
            if artworkURL != nil {
                break
            }
        }
        guard let artworkURL else {
            return hadTransientFailure ? .transientFailure : .notFound
        }

        var request = URLRequest(url: artworkURL)
        request.timeoutInterval = 4
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard Self.isAllowedArtworkURL(artworkURL),
              let (data, response) = try? await session.data(for: request),
              Self.accepts(
                response: response,
                dataCount: data.count,
                maximumBytes: Self.maximumArtworkBytes,
                endpoint: .artwork
              ),
              Self.isValidArtworkData(data) else {
            return .transientFailure
        }
        return .success(data)
    }

    static func searchURL(
        title: String,
        artist: String?,
        countryCode: String?
    ) -> URL? {
        var components = URLComponents(
            string: "https://itunes.apple.com/search"
        )
        let term = [artist, title]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        var queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "8")
        ]
        if let countryCode,
           countryCode.count == 2 {
            queryItems.append(URLQueryItem(
                name: "country",
                value: countryCode.uppercased()
            ))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    static func artworkURL(
        from searchData: Data,
        matching observation: AppleMusicObservation
    ) -> URL? {
        guard searchData.count <= maximumSearchResponseBytes,
              let response = try? JSONDecoder().decode(
                SearchResponse.self,
                from: searchData
              ),
              let title = observation.title,
              let artist = observation.artist,
              !artist.isEmpty else {
            return nil
        }
        let expectedTitle = normalized(title)
        let expectedArtist = normalized(artist)
        let expectedAlbum = observation.album.map(normalized)

        let candidates = response.results.compactMap { result -> URL? in
            guard normalized(result.trackName) == expectedTitle,
                  normalized(result.artistName) == expectedArtist,
                  let artworkURL = result.artworkUrl100 else {
                return nil
            }
            if let expectedAlbum, !expectedAlbum.isEmpty {
                guard result.collectionName.map(normalized) == expectedAlbum else {
                    return nil
                }
            }
            let upscaledURL = upscaledArtworkURL(artworkURL)
            return isAllowedArtworkURL(upscaledURL) ? upscaledURL : nil
        }
        let uniqueCandidates = Array(Set(candidates))
        guard uniqueCandidates.count == 1 else { return nil }
        return uniqueCandidates[0]
    }

    static func upscaledArtworkURL(_ url: URL) -> URL {
        let value = url.absoluteString.replacingOccurrences(
            of: #"/\d+x\d+bb\."#,
            with: "/600x600bb.",
            options: .regularExpression
        )
        return URL(string: value) ?? url
    }

    static func isValidArtworkData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              data.count <= maximumArtworkBytes,
              let imageSource = CGImageSourceCreateWithData(
                data as CFData,
                nil
              ),
              CGImageSourceGetCount(imageSource) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(
                imageSource,
                0,
                nil
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue.isFinite,
              height.doubleValue.isFinite,
              width.doubleValue > 0,
              height.doubleValue > 0,
              width.doubleValue <= maximumArtworkPixels,
              height.doubleValue <= maximumArtworkPixels else {
            return false
        }
        return NSImage(data: data) != nil
    }

    private enum SearchArtworkURLResult {
        case success(URL)
        case notFound
        case transientFailure
    }

    private enum Endpoint {
        case search
        case artwork
    }

    private func searchArtworkURL(
        at url: URL?,
        matching observation: AppleMusicObservation
    ) async -> SearchArtworkURLResult {
        guard let url,
              Self.isAllowedSearchURL(url) else { return .transientFailure }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              Self.accepts(
                response: response,
                dataCount: data.count,
                maximumBytes: Self.maximumSearchResponseBytes,
                endpoint: .search
              ) else {
            return .transientFailure
        }
        guard let artworkURL = Self.artworkURL(
            from: data,
            matching: observation
        ) else {
            return .notFound
        }
        return .success(artworkURL)
    }

    private static func accepts(
        response: URLResponse,
        dataCount: Int,
        maximumBytes: Int,
        endpoint: Endpoint
    ) -> Bool {
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              response.url.map({ url in
                switch endpoint {
                case .search:
                    return isAllowedSearchURL(url)
                case .artwork:
                    return isAllowedArtworkURL(url)
                }
              }) == true,
              dataCount > 0,
              dataCount <= maximumBytes else {
            return false
        }
        let expectedLength = response.expectedContentLength
        return expectedLength <= 0 || expectedLength <= maximumBytes
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return folded.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    static func isAllowedNetworkURL(_ url: URL) -> Bool {
        isAllowedSearchURL(url) || isAllowedArtworkURL(url)
    }

    private static func isAllowedSearchURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "itunes.apple.com"
    }

    private static func isAllowedArtworkURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "mzstatic.com" || host.hasSuffix(".mzstatic.com")
    }
}
