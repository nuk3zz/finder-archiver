# Finder Archiver

A small native macOS interface for the official 7-Zip command-line engine. It works offline and uses the same actions in its window and in Finder.

## Use in Finder

1. Build the app below, move **Finder Archiver.app** to **Applications**, and open it once.
2. In **System Settings → General → Login Items & Extensions → Finder Extensions**, enable **Finder Archiver**. You can also search System Settings for “Finder Extensions.”
3. Right-click files or folders and open **Finder Archiver**.

| Finder selection | Actions |
| --- | --- |
| One or more archives | List Contents, Test Archive, Extract Here, Compress to ZIP, Compress to 7z |
| Other files or folders | Compress to ZIP, Compress to 7z |

**Extract Here** puts each archive into a folder beside it. Existing folders and archives are preserved. Compression combines the selection into one new archive. Individually selected items are stored at the top level. Select their containing folders to preserve folder structure or include same-named files from different folders. Testing checks archive integrity without extracting files.

You can also open the app and choose or drop files into its window. The window allows archive commands on files with unfamiliar extensions. This version has no password-entry interface.

Finder can omit extension menus in locations managed by another extension or in special Finder views. The main app still works with files you select there.

## Build locally

Requires macOS 13 or later and Apple’s Command Line Tools. Run `xcode-select --install` if the tools are missing.

```sh
git clone https://github.com/nuk3zz/finder-archiver.git
cd finder-archiver
./scripts/build.sh
open "build/$(uname -m)/Finder Archiver.app"
```

The build fetches 7-Zip 26.06 from the official upstream release and verifies its published SHA-256 before packaging it. It builds for your Mac’s architecture by default. Set `ARCH=x86_64` or `ARCH=arm64` to select a different target. Local builds are ad hoc signed. Developer ID signing and notarization are separate distribution steps.

## Source and licenses

The Swift app and Finder extension are provided under the [MIT license](LICENSE). Finder Archiver is an independent project. The 7-Zip executable runs as a separate process and retains its upstream licenses, included in the app bundle. Upstream publishes the [official downloads](https://www.7-zip.org/download.html), the [release with checksums and source archive](https://github.com/ip7z/7zip/releases/tag/26.06) and the [source tree at that version](https://github.com/ip7z/7zip/tree/26.06).
