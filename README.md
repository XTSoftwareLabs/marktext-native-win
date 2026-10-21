# MarkText Native for Windows

Native Windows x64 builds of [MarkText](https://github.com/marktext/marktext),
compiled from MarkText's unchanged source with
[NativeBoat](https://github.com/XTSoftwareLabs/nativeboat-release). The
executable runs without Chromium, WebView2 or Node.js.

Download a build from the [releases](../../releases) page.

## Compared with the Electron build

MarkText v0.20.0 native release against the official Electron build
(`marktext-win-x64-0.20.0`):

| Metric | Electron | Native | Change |
|---|---:|---:|---:|
| Download (ZIP) | 176.0 MB | 91.4 MB | 48% smaller |
| Installed folder | 458.7 MB | 285.2 MB | 38% smaller |
| Files on disk | 108 | 23 | 79% fewer |
| Time to window | 782 ms | 161 ms | 4.9× faster |
| Time to open a document | 1,399 ms | 1,000 ms | 29% faster |
| CPU time to start | 2.92 s | 0.84 s | 71% less |
| CPU when idle | 0.23% | 0.00% | 100% less |
| Processes | 5 | 1 | 80% fewer |
| Memory (working set) | 451.1 MB | 280.2 MB | 38% less |
| Memory (private bytes) | 285.9 MB | 208.2 MB | 27% less |
| Threads | 111 | 8 | 93% fewer |
| Handles | 2,194 | 227 | 90% fewer |

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
