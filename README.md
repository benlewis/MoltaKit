# MoltaKit (iOS / macOS / tvOS)

The runtime client for [Molta](../../README.md). Your app connects to a
portal with its **6-digit access code** and pulls the latest *finalized* assets
on launch — no Auth0 login required in the app.

> Other platforms (Android/Kotlin, Unity/C#, web/JS) speak the same
> `/api/sdk/manifest` contract; this is the reference implementation.

## Install (Swift Package Manager)

In Xcode: **File ▸ Add Package Dependencies…**, paste the URL below, and add the
`MoltaKit` product to your target. Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/benlewis/MoltaKit.git", from: "0.2.2"),
],
targets: [
    .target(name: "MyGame", dependencies: ["MoltaKit"]),
]
```

> Versions are git tags on that repo (semver). `from: "0.2.2"` picks up
> compatible updates automatically.

## Usage

```swift
import MoltaKit

let portal = MoltaClient(
    baseURL: URL(string: "https://molta.dev")!,
    accessCode: "428193"   // shown prominently in the portal UI
)

// On launch — downloads only what changed (diffed by checksum), caches the rest.
let synced = try await portal.sync()
for asset in synced where asset.didUpdate {
    print("Updated \(asset.key) → v\(asset.version)")
}

// Use an asset anywhere by its stable key:
if let url = portal.localURL(forKey: "hero_idle") {
    let image = UIImage(contentsOfFile: url.path)
}
if let wav = portal.data(forKey: "laser_shot") {
    // feed bytes to your audio engine
}
```

### How sync works (development)
1. `GET /api/sdk/manifest` with the `X-Access-Code` header returns the published
   asset list, each with a `checksum` and a short-lived signed download `url`.
2. For every asset whose checksum differs from the local cache, the file is
   downloaded into `Caches/Molta/<accessCode>/` and the version map updated.
3. Unchanged assets are skipped, so repeat launches are cheap and offline-friendly
   (the cache persists between runs).

## Development vs. production

The over-the-air downloader is for **DEV/TEST** builds only. For production you
**bake** the finalized assets into the app so the shipped binary has no network
or portal dependency.

| Mode | Behaviour |
| --- | --- |
| `.development` | `sync()` downloads the latest published assets from the portal. |
| `.production` | `sync()` loads assets baked into the app bundle; no network. |
| `.automatic` (default) | `.development` on **DEBUG** builds, `.production` otherwise. |

So with the default, your debug builds pull live updates and your **release**
builds use the baked assets — automatically. Override when needed:

```swift
let portal = MoltaClient(baseURL: url, accessCode: "428193", mode: .production)
```

> TestFlight/Ad-hoc builds compile in Release (`.production`). If you want a test
> build to keep downloading, pass `mode: .development` behind your own build flag.

### Baking for production
1. Confirm you're ready, then bake (mark every asset **Done** first):
   ```bash
   molta status                                   # READY / NOT READY report
   molta bake --out MoltaBaked --require-final
   ```
   This writes each finalized asset, `molta-manifest.json`, **and a
   generated `MoltaBaked.swift`** into the `MoltaBaked/` folder.
2. Drag `MoltaBaked` into your Xcode app target (a **group** so the `.swift`
   compiles and the files bundle).
3. Ship. Two levels of "no network in production":

   **(a) Keep MoltaKit linked** — in release builds the downloader is
   already compiled out (`#if DEBUG || MOLTA_LIVE`), so `sync()` /
   `localURL(forKey:)` just resolve to the bundled files.

   **(b) Exclude the library entirely** — use the generated accessor, which has
   zero dependencies, and only import MoltaKit in DEBUG:
   ```swift
   #if DEBUG
   import MoltaKit
   let portal = MoltaClient(baseURL: url, accessCode: "428193")
   func assetURL(_ k: String) -> URL? { portal.localURL(forKey: k) }
   // …call try await portal.sync() on launch
   #else
   func assetURL(_ k: String) -> URL? { MoltaBaked.url(forKey: k) }   // no library
   #endif
   ```
   Link the MoltaKit package **only in your Debug configuration** and the
   release binary contains none of it.

> **`MOLTA_LIVE`**: define this compilation flag to force the downloader on
> in a release build (e.g. a TestFlight build that should still pull live updates).

## Schema versioning (don't let old apps break)

Each portal has an **asset schema version**. When you ship support for new asset
types in your app, bump it on the server with the CLI:

```bash
molta bump-version           # or: molta seed new.json --bump
```

Build your app declaring the version it understands:

```swift
let portal = MoltaClient(baseURL: url, accessCode: "428193",
                               supportedSchemaVersion: 3)
```

If the portal's version is higher than the app's, `sync()` throws
`MoltaError.appOutOfDate` instead of serving assets the old build can't
handle — show its message and prompt the user to update:

```swift
do {
    try await portal.sync()
} catch let error as MoltaError {
    if case .appOutOfDate = error {
        showUpdateRequiredAlert(message: error.localizedDescription)
    }
}
```

So: new asset types → `supportedSchemaVersion: N` in the new app build **and**
`molta bump-version` on the server. Old builds (supporting < N) are told
to update; current builds keep working.

### Notes
* Only assets the developer has **finalized** (or initial **placeholders**) are
  served — in-review uploads never reach the app.
* `metadata` carries the developer's structured requirements/probe data
  (`width`, `height`, `duration_sec`, …) as flexible `JSONValue`s.
* `sync()` is `async` and safe to call on every launch; wrap it in a `Task`.

## Test
```bash
cd swift/MoltaKit && swift test
```
