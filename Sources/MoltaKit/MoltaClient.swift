import Foundation

public enum MoltaError: Error, LocalizedError {
    case invalidAccessCode
    case network(Int, String)
    case decoding(String)
    case download(String)
    case bakedManifestMissing
    /// The portal's assets require a newer app build than this one supports.
    case appOutOfDate(required: Int, supported: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidAccessCode: return "The access code was rejected by the portal."
        case .network(let code, let msg): return "Portal request failed (\(code)): \(msg)"
        case .decoding(let m): return "Could not read the portal response: \(m)"
        case .download(let m): return "Asset download failed: \(m)"
        case .bakedManifestMissing:
            return "Production build is missing baked assets. Run `molta bake` and add the "
                + "MoltaBaked folder to your app target."
        case .appOutOfDate(let required, let supported):
            return "This version of the app is out of date — please update to the latest version. "
                + "(needs asset schema v\(required), this build supports v\(supported))"
        }
    }
}

/// Client for a Molta portal. Connect with the portal's 6-digit access code,
/// call `sync()` on launch, then look assets up by key.
///
/// In **development** (DEBUG) builds it downloads the latest published assets
/// from the portal. In **production** (release) builds it loads assets that were
/// baked into the app bundle with `molta bake` — no network, no portal
/// dependency. The behaviour is chosen automatically; override with `mode`.
///
/// ```swift
/// let portal = MoltaClient(baseURL: URL(string: "https://molta.dev")!,
///                                accessCode: "428193")          // mode: .automatic
/// let assets = try await portal.sync()
/// if let hero = portal.localURL(forKey: "hero_idle") { /* load from disk */ }
/// ```
public final class MoltaClient {
    private let baseURL: URL
    private let accessCode: String
    private let session: URLSession
    private let cache: AssetCache

    /// Resolved mode (`.automatic` collapses to `.development`/`.production`).
    public let mode: MoltaMode
    /// The asset-schema version this app build understands. If the portal's
    /// version is higher, `sync()` throws `.appOutOfDate` instead of serving
    /// assets the app can't handle. Bump it (and your portal via the CLI) when
    /// you ship support for new asset types.
    public let supportedSchemaVersion: Int
    private let bundle: Bundle
    private let bakedSubdirectory: String?
    private var bakedURLs: [String: URL] = [:]
    private var bakedLoaded = false

    public init(
        baseURL: URL,
        accessCode: String,
        supportedSchemaVersion: Int = 1,
        mode: MoltaMode = .automatic,
        bundle: Bundle = .main,
        bakedSubdirectory: String? = "MoltaBaked",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.accessCode = accessCode
        self.supportedSchemaVersion = supportedSchemaVersion
        self.session = session
        self.cache = AssetCache(accessCode: accessCode)
        self.bundle = bundle
        self.bakedSubdirectory = bakedSubdirectory
        self.mode = MoltaClient.resolve(mode)
    }

    static func resolve(_ mode: MoltaMode) -> MoltaMode {
        guard mode == .automatic else { return mode }
        // MOLTA_LIVE forces live downloads even in a release build (e.g. a
        // TestFlight build that should keep pulling the latest assets), so the
        // flag alone is enough — no need to also pass `mode: .development`.
        #if DEBUG || MOLTA_LIVE
        return .development
        #else
        return .production
        #endif
    }

    /// In development: fetch the published manifest and download new/changed
    /// assets (diffed by checksum). In production: load the baked, bundled
    /// assets — no network. Returns every asset now available locally.
    @discardableResult
    public func sync() async throws -> [SyncedAsset] {
        // The downloader is compiled out of production builds. Define the
        // MOLTA_LIVE compilation flag to force it on in a release build
        // (e.g. a TestFlight build that should still pull live updates).
        #if DEBUG || MOLTA_LIVE
        if mode == .development { return try await developmentSync() }
        #endif
        return try loadBaked()
    }

    /// Local file URL for an asset: the downloaded cache (development) or the
    /// bundled baked file (production). Returns nil if not available.
    public func localURL(forKey key: String) -> URL? {
        #if DEBUG || MOLTA_LIVE
        if mode == .development { return cache.fileURL(forKey: key) }
        #endif
        if !bakedLoaded { _ = try? loadBaked() }
        return bakedURLs[key]
    }

    /// Raw bytes for an asset, or nil if not available.
    public func data(forKey key: String) -> Data? {
        guard let url = localURL(forKey: key) else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: - Production (baked) loading

    @discardableResult
    private func loadBaked() throws -> [SyncedAsset] {
        guard let manifestURL = findBaked(name: "molta-manifest", ext: "json") else {
            throw MoltaError.bakedManifestMissing
        }
        let manifest = try JSONDecoder().decode(BakedManifest.self, from: Data(contentsOf: manifestURL))
        var results: [SyncedAsset] = []
        for entry in manifest.assets {
            let name = (entry.file as NSString).deletingPathExtension
            let ext = (entry.file as NSString).pathExtension
            guard let url = findBaked(name: name, ext: ext) else { continue }
            bakedURLs[entry.key] = url
            results.append(SyncedAsset(key: entry.key, name: entry.name, type: entry.type,
                                       version: entry.version, localURL: url,
                                       metadata: entry.metadata ?? [:], didUpdate: false))
        }
        bakedLoaded = true
        return results
    }

    /// Find a baked resource whether the folder was added as a folder reference
    /// (subdirectory) or a group (flattened into the bundle root).
    private func findBaked(name: String, ext: String) -> URL? {
        if let sub = bakedSubdirectory,
           let url = bundle.url(forResource: name, withExtension: ext, subdirectory: sub) {
            return url
        }
        return bundle.url(forResource: name, withExtension: ext)
    }

    // MARK: - Networking (development / test builds only)
    #if DEBUG || MOLTA_LIVE

    /// Fetch the published manifest and download new/changed assets.
    private func developmentSync() async throws -> [SyncedAsset] {
        let manifest = try await fetchManifest()
        // Refuse to serve assets that need a newer app than this build supports.
        guard manifest.schemaVersion <= supportedSchemaVersion else {
            throw MoltaError.appOutOfDate(required: manifest.schemaVersion,
                                                supported: supportedSchemaVersion)
        }
        // Serve cache hits immediately; download the rest concurrently (bounded)
        // so a large portal doesn't sync one slow file at a time.
        var results: [SyncedAsset] = []
        var toDownload: [ManifestEntry] = []
        for entry in manifest.assets {
            if cache.isCurrent(entry), let url = cache.fileURL(forKey: entry.key) {
                results.append(SyncedAsset(key: entry.key, name: entry.name, type: entry.type,
                                           version: entry.version, localURL: url,
                                           metadata: entry.metadata, didUpdate: false))
            } else {
                toDownload.append(entry)
            }
        }

        // Download concurrently (bounded) but write to the cache serially on this
        // task — AssetCache holds mutable state and isn't safe for parallel writes.
        let maxConcurrent = 6
        try await withThrowingTaskGroup(of: (ManifestEntry, Data).self) { group in
            var index = 0
            func addTask(_ entry: ManifestEntry) {
                group.addTask { (entry, try await self.download(entry)) }
            }
            while index < min(maxConcurrent, toDownload.count) {
                addTask(toDownload[index]); index += 1
            }
            while let (entry, data) = try await group.next() {
                let url = try cache.store(data, for: entry)
                results.append(SyncedAsset(key: entry.key, name: entry.name, type: entry.type,
                                           version: entry.version, localURL: url,
                                           metadata: entry.metadata, didUpdate: true))
                if index < toDownload.count { addTask(toDownload[index]); index += 1 }
            }
        }
        return results
    }

    func fetchManifest() async throws -> Manifest {
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/v1/sdk/manifest"))
        req.setValue(accessCode, forHTTPHeaderField: "X-Access-Code")
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw MoltaError.network(-1, "No HTTP response")
        }
        if http.statusCode == 401 { throw MoltaError.invalidAccessCode }
        guard (200..<300).contains(http.statusCode) else {
            throw MoltaError.network(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do { return try JSONDecoder().decode(Manifest.self, from: data) }
        catch { throw MoltaError.decoding("\(error)") }
    }

    private func download(_ entry: ManifestEntry) async throws -> Data {
        guard let url = URL(string: entry.url) else {
            throw MoltaError.download("Bad URL for \(entry.key)")
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MoltaError.download("HTTP error downloading \(entry.key)")
        }
        return data
    }

    #endif // DEBUG || MOLTA_LIVE
}
