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
            let encoded = keywords.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keywords
            guard let url = URL(string: "https://neteasecloudmusicapi-ten-wine.vercel.app/search?keywords=\(encoded)&limit=\(limit)") else {
                throw URLError(.badURL)
            }
            let (data, _) = try await session.data(from: url)
            return try JSONDecoder().decode(NetEaseSearch.self, from: data)
        }
    }

    private func doLyric(id: Int) async throws -> NetEaseLyrics {
        if useDirect {
            var req = URLRequest(url: URL(string: "https://music.163.com/api/song/lyric?id=\(id)&lv=-1&tv=-1")!)
            req.setValue("MUSIC_U=\(musicU); __csrf=\(csrf)", forHTTPHeaderField: "Cookie")
            let (data, _) = try await session.data(for: req)
            return try JSONDecoder().decode(NetEaseLyrics.self, from: data)
        } else {
            let url = URL(string: "https://neteasecloudmusicapi-ten-wine.vercel.app/lyric?id=\(id)")!
            let (data, _) = try await session.data(from: url)
            return try JSONDecoder().decode(NetEaseLyrics.self, from: data)
        }
    }

    // Strips (…)/[…] annotations then folds case, diacritics, and full-width chars.
    private func normalize(_ s: String) -> String {
        var r = s.trimmingCharacters(in: .whitespaces)
        r = r.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        r = r.replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
        return r.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
    }

    // Returns true if any component of candidate matches any component of query,
    // splitting on common multi-artist separators (&, feat., ft., ×).
    private func artistMatches(_ candidate: String, _ query: String) -> Bool {
        let cn = normalize(candidate), qn = normalize(query)
        guard cn != qn else { return true }
        func parts(_ s: String) -> [String] {
            s.components(separatedBy: CharacterSet(charactersIn: "&,×"))
             .flatMap { $0.components(separatedBy: " feat. ") }
             .flatMap { $0.components(separatedBy: " ft. ") }
             .map { $0.trimmingCharacters(in: .whitespaces) }
             .filter { !$0.isEmpty }
        }
        return parts(cn).contains { c in parts(qn).contains { c == $0 } }
    }

    // Aligns tlyric timestamps to main lyric lines within a 2-second window.
    private func alignedTranslation(main: [LyricLine], tlyricString: String?) -> [String] {
        guard let raw = tlyricString, !raw.isEmpty else { return [] }
        let tLines = LyricsParser(lyrics: raw).lyrics
        guard !tLines.isEmpty else { return [] }
        let result = main.map { mainLine -> String in
            guard let closest = tLines.min(by: {
                abs($0.startTimeMS - mainLine.startTimeMS) < abs($1.startTimeMS - mainLine.startTimeMS)
            }), abs(closest.startTimeMS - mainLine.startTimeMS) < 2000 else { return "" }
            return closest.words
        }
        return result.contains(where: { !$0.isEmpty }) ? result : []
    }

    // MARK: - LyricProvider

    func fetchNetworkLyrics(trackName: String, trackID: String, currentlyPlayingArtist: String?, currentAlbumName: String?) async throws -> NetworkFetchReturn {
        guard let artist = currentlyPlayingArtist else {
            return NetworkFetchReturn(lyrics: [], colorData: nil)
        }

        let searchResult = try await doSearch(keywords: "\(trackName) \(artist)", limit: 5)

        guard let song = searchResult.result.songs.first(where: { song in
            normalize(song.name) == normalize(trackName) &&
            artistMatches(song.artists.first?.name ?? "", artist)
        }) else {
            return NetworkFetchReturn(lyrics: [], colorData: nil)
        }

        let lyricData = try await doLyric(id: song.id)
        guard let lrcString = lyricData.lrc?.lyric else {
            return NetworkFetchReturn(lyrics: [], colorData: nil)
        }
        let parser = LyricsParser(lyrics: lrcString)
        guard parser.lyrics.last?.startTimeMS != 0.0 else {
            return NetworkFetchReturn(lyrics: [], colorData: nil)
        }
        let translation = alignedTranslation(main: parser.lyrics, tlyricString: lyricData.tlyric?.lyric)
        return NetworkFetchReturn(lyrics: parser.lyrics, colorData: nil, translation: translation)
    }

    func search(trackName: String, artistName: String) async throws -> [SongResult] {
        let searchResult = try await doSearch(keywords: "\(trackName) \(artistName)", limit: 5)
        var results: [SongResult] = []
        for song in searchResult.result.songs {
            guard let firstArtist = song.artists.first else { continue }
            do {
                let lyricData = try await doLyric(id: song.id)
                guard let lrcText = lyricData.lrc?.lyric else { continue }
                let parsed = LyricsParser(lyrics: lrcText).lyrics
                guard parsed.last?.startTimeMS != 0.0 else { continue }
                let translation = alignedTranslation(main: parsed, tlyricString: lyricData.tlyric?.lyric)
                results.append(SongResult(lyricType: "NetEase", songName: song.name, albumName: song.album.name, artistName: firstArtist.name, lyrics: parsed, translation: translation))
            } catch {
                // ignore per-item failure
            }
        }
        return results
    }
}
