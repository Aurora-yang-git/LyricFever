//
//  NetworkFetchReturn.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-08-06.
//

struct NetworkFetchReturn {
    let lyrics: [LyricLine]
    let colorData: Int32?
    var translation: [String] = []

    func processed(withSongName songName: String, duration: Int) -> NetworkFetchReturn {
        var filteredLyrics: [LyricLine] = []
        var filteredTranslation: [String] = []

        for (i, line) in lyrics.enumerated() {
            if !line.words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                filteredLyrics.append(line)
                if !translation.isEmpty, i < translation.count {
                    filteredTranslation.append(translation[i])
                }
            }
        }

        guard lyrics.count > 1 else {
            return self
        }

        let nowPlayingLine = LyricLine(startTime: Double(duration + 5000), words: "Now Playing: \(songName)")
        let finalTranslation = filteredTranslation.isEmpty ? [] : filteredTranslation + [""]
        return NetworkFetchReturn(lyrics: filteredLyrics + [nowPlayingLine], colorData: colorData, translation: finalTranslation)
    }
}
