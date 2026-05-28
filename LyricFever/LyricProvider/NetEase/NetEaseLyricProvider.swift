//
//  NetEaseLyricsProvider.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-06-16.
//

import Foundation

class NetEaseLyricProvider: LyricProvider {
    var providerName = "NetEase Lyric Provider"

    private var musicU: String { UserDefaults.standard.string(forKey: "neteaseMusicU") ?? "" }
    private var csrf: String { UserDefaults.standard.string(forKey: "neteaseCsrf") ?? "" }
    private var useDirect: Bool { !musicU.isEmpty && !csrf.isEmpty }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15",
            "Referer": "https://music.163.com/"
        ]
        return URLSession(configuration: config)
    }()

    // MARK: - Endpoint helpers

    private func doSearch(keywords: String, limit: Int) async throws -> NetEaseSearch {
        if useDirect {
            var req = URLRequest(url: URL(string: "https://music.163.com/api/search/get")!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.setValue("MUSIC_U=\(musicU); __csrf=\(csrf)", forHTTPHeaderField: "Cookie")
            let encoded = keywords.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keywords
            req.httpBody = "s=\(encoded)&type=1&limit=\(limit)&offset=0&csrf_token=\(csrf)".data(using: .utf8)
            let (data, _) = try await session.data(for: req)
            return try JSONDecoder().decode(NetEaseSearch.self, from: data)
        } else {
            let encoded = keywords.replacingOccurrences(of: "&", with: "%26")
            let url = URL(string: "https://neteasecloudmusicapi-ten-wine.vercel.app/search?keywords=\(encoded)&limit=\(limit)")!
            let (data, _) = try await session.data(from: url)
            return try JSONDecoder().decode(NetEaseSearch.self, from: data)
        }
    }

    private func doLyric(id: Int) async throws -> NetEaseLyrics {
        if useDirect {
            var req = URLRequest(url: URL(string: "https://music.163.com/api/song/lyric?id=\(id)&lv=1")!)
            req.setValue("MUSIC_U=\(musicU); __csrf=\(csrf)", forHTTPHeaderField: "Cookie")
            let (data, _) = try await session.data(for: req)
            return try JSONDecoder().decode(NetEaseLyrics.self, from: data)
        } else {
            let url = URL(string: "https://neteasecloudmusicapi-ten-wine.vercel.app/lyric?id=\(id)")!
            let (data, _) = try await session.data(from: url)
            return try JSONDecoder().decode(NetEaseLyrics.self, from: data)
        }
    }

    // MARK: - LyricProvider

    func fetchNetworkLyrics(trackName: String, trackID: String, currentlyPlayingArtist: String?, currentAlbumName: String?) async throws -> NetworkFetchReturn {
        guard let artist = currentlyPlayingArtist, let album = currentAlbumName else {
            return NetworkFetchReturn(lyrics: [], colorData: nil)
        }
        let keywords = "\(trackName.replacingOccurrences(of: "&", with: "%26")) \(artist.replacingOccurrences(of: "&", with: "%26"))"
        let searchResult = try await doSearch(keywords: keywords, limit: 1)
        guard let song = searchResult.result.songs.first, let firstArtist = song.artists.first else {
            return NetworkFetchReturn(lyrics: [], colorData: nil)
        }

        print("NetEase match check — track: '\(trackName)' vs '\(song.name)', artist: '\(artist)' vs '\(firstArtist.name)', album: '\(album)' vs '\(song.album.name)'")

        guard normalize(trackName) == normalize(song.name),
              normalize(artist) == normalize(firstArtist.name),
              normalize(album) == normalize(song.album.name) else {
            print("NetEase: match failed after normalization, skipping")
            return NetworkFetchReturn(lyrics: [], colorData: nil)
        }

        let lyricData = try await doLyric(id: song.id)
        guard let lrcString = lyricData.lrc?.lyric else {
            return NetworkFetchReturn(lyrics: [], colorData: nil)
        }
        let cleaned = unescapeHTMLEntities(in: lrcString)
        let parser = LyricsParser(lyrics: cleaned)
        // NetEase returns stub lyrics (name/artist only at t=0) for songs without real lyrics
        if parser.lyrics.last?.startTimeMS == 0.0 {
            return NetworkFetchReturn(lyrics: [], colorData: nil)
        }
        let translation = alignedTranslation(main: parser.lyrics, tlyricString: lyricData.tlyric?.lyric)
        return NetworkFetchReturn(lyrics: parser.lyrics, colorData: nil, translation: translation)
    }
}

// MARK: - Search

extension NetEaseLyricProvider {
    func search(trackName: String, artistName: String) async throws -> [SongResult] {
        let keywords = "\(trackName.replacingOccurrences(of: "&", with: "%26")) \(artistName.replacingOccurrences(of: "&", with: "%26"))"
        let searchResult = try await doSearch(keywords: keywords, limit: 5)
        var results: [SongResult] = []
        for song in searchResult.result.songs {
            guard let firstArtist = song.artists.first else { continue }
            do {
                let lyricData = try await doLyric(id: song.id)
                guard let lrcText = lyricData.lrc?.lyric else { continue }
                let cleaned = unescapeHTMLEntities(in: lrcText)
                let parsed = LyricsParser(lyrics: cleaned).lyrics
                if parsed.last?.startTimeMS == 0.0 { continue }
                results.append(SongResult(lyricType: "NetEase", songName: song.name, albumName: song.album.name, artistName: firstArtist.name, lyrics: parsed))
            } catch {
                // ignore per-item failure
            }
        }
        return results
    }
}

// MARK: - Helpers

private func normalize(_ s: String) -> String {
    var result = s
    // Strip bracketed/parenthetical annotations
    result = result.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
    result = result.replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
    // Fold accents, case, full-width (à→a, A→a, ａ→a)
    result = result.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
    // Strip punctuation and symbols
    result = result.unicodeScalars
        .filter { !CharacterSet.punctuationCharacters.union(.symbols).contains($0) }
        .reduce("") { $0 + String($1) }
    // Collapse whitespace
    return result.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
}

private func alignedTranslation(main: [LyricLine], tlyricString: String?) -> [String] {
    guard let raw = tlyricString, !raw.isEmpty else { return [] }
    let tLines = LyricsParser(lyrics: unescapeHTMLEntities(in: raw)).lyrics
    guard !tLines.isEmpty else { return [] }
    return main.map { mainLine in
        guard let closest = tLines.min(by: {
            abs($0.startTimeMS - mainLine.startTimeMS) < abs($1.startTimeMS - mainLine.startTimeMS)
        }), abs(closest.startTimeMS - mainLine.startTimeMS) < 2000 else { return "" }
        return closest.words
    }
}

private func unescapeHTMLEntities(in text: String) -> String {
    var s = text
    s = s.replacingOccurrences(of: "&apos;", with: "'")
    s = s.replacingOccurrences(of: "&quot;", with: "\"")
    s = s.replacingOccurrences(of: "&amp;", with: "&")
    s = s.replacingOccurrences(of: "&lt;", with: "<")
    s = s.replacingOccurrences(of: "&gt;", with: ">")
    s = s.replacingOccurrences(of: "&#39;", with: "'")
    s = s.replacingOccurrences(of: "&#x27;", with: "'")
    s = s.replacingOccurrences(of: "\\\n", with: "\n")
    return s
}
