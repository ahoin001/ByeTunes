import AVFoundation
import Foundation

/// Tag snapshot captured from the source file (same timing as Music import).
struct PreservedTrackMetadata: Equatable {
    var title: String
    var artist: String
    var album: String
    var albumArtist: String?
    var genre: String
    var year: Int
    var durationMs: Int
    var trackNumber: Int?
    var trackCount: Int?
    var discNumber: Int?
    var discCount: Int?
    var lyrics: String?
    var artworkData: Data?

    init(from song: SongMetadata) {
        title = song.title
        artist = song.artist
        album = song.album
        albumArtist = song.albumArtist
        genre = song.genre
        year = song.year
        durationMs = song.durationMs
        trackNumber = song.trackNumber
        trackCount = song.trackCount
        discNumber = song.discNumber
        discCount = song.discCount
        lyrics = song.lyrics
        artworkData = song.artworkData
    }

    func makeSongMetadata(for outputURL: URL) -> SongMetadata {
        let ext = outputURL.pathExtension.lowercased()
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        return SongMetadata(
            localURL: outputURL,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            year: year,
            durationMs: durationMs,
            fileSize: fileSize,
            remoteFilename: SongMetadata.generateRemoteFilename(withExtension: ext.isEmpty ? "m4a" : ext),
            artworkData: artworkData,
            trackNumber: trackNumber,
            trackCount: trackCount,
            discNumber: discNumber,
            discCount: discCount,
            lyrics: lyrics
        )
    }
}

enum AudioMetadataPreservation {
    static func capture(from url: URL) async -> PreservedTrackMetadata? {
        if let song = try? await SongMetadata.fromURL(url, includeArtwork: true) {
            return PreservedTrackMetadata(from: song)
        }
        return nil
    }

    /// Re-embeds tags from the tagged source file onto the converted output (FFmpeg copy-mux).
    static func copyTagsFromSource(sourceURL: URL, outputURL: URL) async throws {
        guard FFmpegTranscoder.isAvailable else { return }

        let tempURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString)_tagged.\(outputURL.pathExtension)")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let command = [
            "-y",
            "-i", "\"\(outputURL.path)\"",
            "-i", "\"\(sourceURL.path)\"",
            "-map", "0:a",
            "-map_metadata", "1",
            "-c", "copy",
            "-movflags", "+faststart",
            "\"\(tempURL.path)\""
        ].joined(separator: " ")

        try await FFmpegTranscoder.runCommand(command)

        if FileManager.default.fileExists(atPath: tempURL.path) {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: outputURL)
        }
    }

    static func applyExportSessionMetadata(from sourceURL: URL, to session: AVAssetExportSession) async {
        let asset = AVURLAsset(url: sourceURL)
        if let metadata = try? await asset.load(.metadata), !metadata.isEmpty {
            session.metadata = metadata
        }
    }
}
