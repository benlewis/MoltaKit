import Foundation

/// A minimal JSON value so arbitrary asset `metadata` can be decoded without a
/// fixed schema (e.g. {"width":1024,"loop":true}).
public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }

    public var intValue: Int? { if case .number(let n) = self { return Int(n) }; return nil }
    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
}

/// One published asset as returned by `/api/sdk/manifest`.
public struct ManifestEntry: Codable, Equatable {
    public let key: String
    public let name: String
    public let type: String
    public let version: Int
    public let checksum: String?
    public let size: Int?
    public let mimeType: String?
    public let url: String
    public let metadata: [String: JSONValue]
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case key, name, type, version, checksum, size, url, metadata
        case mimeType = "mime_type"
        case updatedAt = "updated_at"
    }
}

public struct Manifest: Codable {
    public let project: String
    public let accessCode: String
    /// Minimum app build version required to handle these assets.
    public let schemaVersion: Int
    public let generatedAt: String
    public let assets: [ManifestEntry]

    enum CodingKeys: String, CodingKey {
        case project, assets
        case accessCode = "access_code"
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        project = try c.decode(String.self, forKey: .project)
        accessCode = try c.decode(String.self, forKey: .accessCode)
        // Default to 1 for portals that predate schema versioning.
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        generatedAt = try c.decode(String.self, forKey: .generatedAt)
        assets = try c.decode([ManifestEntry].self, forKey: .assets)
    }
}

/// How the client obtains assets.
public enum MoltaMode: Sendable {
    /// DEV/TEST builds: download the latest published assets from the portal.
    case development
    /// PROD builds: load assets baked into the app bundle (no network).
    case production
    /// `.development` on DEBUG builds, `.production` otherwise. The default.
    case automatic
}

/// One entry in a baked manifest (`molta-manifest.json`) produced by
/// `molta bake` and bundled into a production build.
public struct BakedEntry: Codable, Equatable {
    public let key: String
    public let name: String
    public let type: String
    public let version: Int
    public let checksum: String?
    public let file: String                 // file name within the baked folder
    public let metadata: [String: JSONValue]?
}

public struct BakedManifest: Codable {
    public let project: String?
    public let assets: [BakedEntry]
}

/// An asset available locally after a sync.
public struct SyncedAsset: Equatable {
    public let key: String
    public let name: String
    public let type: String
    public let version: Int
    public let localURL: URL
    public let metadata: [String: JSONValue]
    /// True if this sync downloaded a new version (vs. already cached).
    public let didUpdate: Bool
}
