# MarkText Native for Windows

Native Windows x64 builds of [MarkText](https://github.com/marktext/marktext),
compiled from MarkText's unchanged source with
[NativeBoat](https://github.com/XTSoftwareLabs/nativeboat-release). The
executable runs without Chromium, WebView2 or Node.js.

Download a build from the [releases](../../releases) page.

## Compared with the Electron build

MarkText v0.20.0 native release, built with NativeBoat v0.1.0-alpha.2, against
the official Electron build (`marktext-win-x64-0.20.0`):

| Metric | Electron | Native | Change |
|---|---:|---:|---:|
| Download (ZIP) | 166.0 MB | 88.5 MB | 47% smaller |
| Installed folder | 458.7 MB | 274.9 MB | 40% smaller |
| Files on disk | 108 | 23 | 79% fewer |
| Time to window | 794 ms | 150 ms | 5.3× faster |
| Time to open a document | 1,427 ms | 1,018 ms | 29% faster |
| CPU time to start | 2.17 s | 0.89 s | 59% less |
| CPU when idle | 0.21% | 0.00% | 100% less |
| Processes | 5 | 1 | 80% fewer |
| Memory (working set) | 461.3 MB | 279.8 MB | 39% less |
| Memory (private bytes) | 296.0 MB | 207.9 MB | 30% less |
| Threads | 112 | 8 | 93% fewer |
| Handles | 2,205 | 227 | 90% fewer |

Measured on Windows 10 22H2 with an Intel Core i7-8750H and 8 GB of RAM,
opening a short Markdown file. Each figure is the median of three runs.
Memory, threads and handles are summed over all of the app's processes,
15 seconds after the document opened; idle CPU is averaged over the next
10 seconds.

## How it is built

The [Build native MarkText](.github/workflows/build.yml) workflow:

1. checks out a MarkText tag (default `v0.20.0`) from `marktext/marktext`,
2. sets up Node.js and pnpm, which NativeBoat uses to install the project's
   dependencies,
3. compiles `packages/desktop` with the
   [NativeBoat Build action](https://github.com/marketplace/actions/nativeboat-build) (`@v1`),
4. uploads a ZIP of the full output folder and its `SHA256SUMS.txt` as a
   workflow artifact. The executable needs the other files in that folder, so
   it is not published on its own.

The [Release native MarkText](.github/workflows/release.yml) workflow runs that
build and publishes it as a new release. Each release is tagged with the
MarkText tag plus a build number (`v0.20.0.1`, `v0.20.0.2`, ...), so a rebuild,
for example with a newer NativeBoat, never replaces an earlier release.
