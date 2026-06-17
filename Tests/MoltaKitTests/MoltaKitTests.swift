import XCTest
@testable import MoltaKit

final class MoltaKitTests: XCTestCase {

    func testManifestDecoding() throws {
        let json = """
        {
          "project": "Galaxy Raiders",
          "access_code": "428193",
          "generated_at": "2026-06-15T00:00:00Z",
          "assets": [
            {
              "key": "hero_idle",
              "name": "Hero idle",
              "type": "image",
              "version": 3,
              "checksum": "abc123",
              "size": 20480,
              "mime_type": "image/png",
              "url": "https://example.com/file.png?token=x",
              "metadata": {"width": 1024, "height": 1024, "loop": false},
              "updated_at": "2026-06-15T00:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(Manifest.self, from: json)
        XCTAssertEqual(manifest.project, "Galaxy Raiders")
        XCTAssertEqual(manifest.schemaVersion, 1) // absent in JSON → defaults to 1
        XCTAssertEqual(manifest.assets.count, 1)
        let entry = manifest.assets[0]
        XCTAssertEqual(entry.key, "hero_idle")
        XCTAssertEqual(entry.version, 3)
        XCTAssertEqual(entry.mimeType, "image/png")
        XCTAssertEqual(entry.metadata["width"]?.intValue, 1024)
        XCTAssertEqual(entry.metadata["loop"]?.boolValue, false)
    }

    func testCacheRoundTrip() throws {
        let cache = AssetCache(accessCode: "test\(Int.random(in: 0...99999))")
        let entry = ManifestEntry(
            key: "blip", name: "Blip", type: "sound", version: 1,
            checksum: "deadbeef", size: 4, mimeType: "audio/wav",
            url: "https://example.com/blip.wav", metadata: [:], updatedAt: "now"
        )
        XCTAssertFalse(cache.isCurrent(entry))
        let url = try cache.store(Data([0, 1, 2, 3]), for: entry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(cache.isCurrent(entry))
        XCTAssertEqual(cache.fileURL(forKey: "blip"), url)
    }

    func testExtensionFromMime() {
        XCTAssertEqual(AssetCache.ext(forMime: "image/png"), "png")
        XCTAssertEqual(AssetCache.ext(forMime: "audio/wav"), "wav")
        XCTAssertEqual(AssetCache.ext(forMime: "application/octet-stream"), "")
    }

    func testBakedManifestDecoding() throws {
        let json = """
        {
          "project": "Galaxy Raiders",
          "baked_at": "2026-06-16T00:00:00Z",
          "assets": [
            { "key": "hero_ship", "name": "Hero ship", "type": "image", "version": 4,
              "checksum": "abc", "file": "hero_ship.png", "metadata": {"width": 256} }
          ]
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(BakedManifest.self, from: json)
        XCTAssertEqual(manifest.project, "Galaxy Raiders")
        XCTAssertEqual(manifest.assets.first?.file, "hero_ship.png")
        XCTAssertEqual(manifest.assets.first?.metadata?["width"]?.intValue, 256)
    }

    func testModeResolution() {
        XCTAssertEqual(MoltaClient.resolve(.production), .production)
        XCTAssertEqual(MoltaClient.resolve(.development), .development)
        // .automatic collapses to development under DEBUG (test builds).
        XCTAssertEqual(MoltaClient.resolve(.automatic), .development)
    }
}
