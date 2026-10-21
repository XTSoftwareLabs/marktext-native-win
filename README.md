# MarkText Native for Windows

Native Windows x64 builds of [MarkText](https://github.com/marktext/marktext),
compiled from MarkText's unchanged source with
[NativeBoat](https://github.com/XTSoftwareLabs/nativeboat-release). The
executable runs without Chromium, WebView2 or Node.js.

Download a build from the [releases](../../releases) page.

## How it is built

The [Build native MarkText](.github/workflows/build.yml) workflow:

1. checks out a MarkText tag (default `v0.20.0`) from `marktext/marktext`,
2. sets up Node.js and pnpm, which NativeBoat uses to install the project's
   dependencies,
3. compiles `packages/desktop` with the
   [NativeBoat Build action](https://github.com/XTSoftwareLabs/nativeboat-action),
4. publishes the executable, a ZIP of the full output folder and
   `SHA256SUMS.txt` to a release named after the MarkText tag.

Pushes to `main` rebuild and update the release; pull requests build only. To
build another MarkText tag or NativeBoat version, run the workflow manually
from the Actions tab and set `marktext-ref` and `nativeboat-version`.
