import Foundation

/// On-disk cache of downloaded assets + a manifest of what version/checksum we
/// hold for each key. Stored under Caches/Molta/<accessCode>/.
final class AssetCache {
    struct Entry: Codable {
        var version: Int
        var checksum: String?
        var fileName: String
    }

    private let directory: URL
    private let stateURL: URL
    private var state: [String: Entry]

    init(accessCode: String) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = caches.appendingPathComponent("Molta/\(accessCode)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.stateURL = directory.appendingPathComponent("_state.json")

        if let data = try? Data(contentsOf: stateURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            self.state = decoded
        } else {
            self.state = [:]
        }
    }

    func entry(forKey key: String) -> Entry? { state[key] }

    func fileURL(forKey key: String) -> URL? {
        guard let entry = state[key] else { return nil }
        let url = directory.appendingPathComponent(entry.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// True when the cached entry already matches the manifest version+checksum.
    func isCurrent(_ manifest: ManifestEntry) -> Bool {
        guard let entry = state[manifest.key] else { return false }
        guard fileURL(forKey: manifest.key) != nil else { return false }
        if let mc = manifest.checksum, let ec = entry.checksum { return mc == ec }
        return entry.version == manifest.version
    }

    func store(_ data: Data, for manifest: ManifestEntry) throws -> URL {
        let ext = (manifest.url as NSString).pathExtension.isEmpty
            ? Self.ext(forMime: manifest.mimeType) : (manifest.url as NSString).pathExtension
        let fileName = ext.isEmpty ? manifest.key : "\(manifest.key).\(ext)"
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        state[manifest.key] = Entry(version: manifest.version, checksum: manifest.checksum, fileName: fileName)
        persist()
        return url
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    static func ext(forMime mime: String?) -> String {
        switch mime {
        case "image/png": return "png"
        case "image/jpeg": return "jpg"
        case "image/webp": return "webp"
        case "audio/wav", "audio/x-wav": return "wav"
        case "audio/mpeg": return "mp3"
        case "video/mp4": return "mp4"
        case "application/json": return "json"
        default: return ""
        }
    }
}
