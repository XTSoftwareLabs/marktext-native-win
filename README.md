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
4. uploads the executable, a ZIP of the full output folder and
   `SHA256SUMS.txt` as a workflow artifact.

It runs on pushes to `main` and on pull requests, and publishes nothing.

## Releasing

Run the [Release native MarkText](.github/workflows/release.yml) workflow from
the Actions tab. Set `marktext-ref` to the MarkText tag to build and
`nativeboat-version` to a NativeBoat release tag or `latest`. It runs the build
above, then publishes its files to a release named after the MarkText tag.
Running it again for the same tag replaces that release's files.
