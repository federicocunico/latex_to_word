# LaTeX to Word Converter

A Flutter desktop application that converts Overleaf ZIP exports to `.docx` files using [pandoc](https://pandoc.org).

Drop or open any `.zip` downloaded from Overleaf. The app finds `main.tex`, resolves bibliography files and image paths, runs pandoc, and lets you save the resulting Word document — no Docker, no Python, no server.

**pandoc is downloaded automatically on first launch** (~35 MB, stored in your application support directory and reused for every subsequent run).

---

## Supported platforms

| Platform | Status |
|----------|--------|
| Windows (x64) | ? |
| macOS (x64 / arm64) | ? |
| Linux (x64) | ? |

---

## Prerequisites

### All platforms
- [Flutter SDK](https://docs.flutter.dev/get-started/install) **3.x or later** (stable channel)
- Internet connection on first launch (to download pandoc)

### Windows
- [Visual Studio 2022](https://visualstudio.microsoft.com/) with the **Desktop development with C++** workload

### macOS
- Xcode 14+ (from the Mac App Store)
- `xcode-select --install` for command-line tools

### Linux
- `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`

  ```sh
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
  ```

---

## Build from source

```sh
# 1. Clone
git clone https://github.com/your-org/latex_to_word.git
cd latex_to_word

# 2. Fetch Dart dependencies
flutter pub get

# 3. Build a release executable
flutter build windows --release   # Windows
flutter build macos   --release   # macOS
flutter build linux   --release   # Linux
```

Output lands in:

| Platform | Path |
|----------|------|
| Windows | `build/windows/x64/runner/Release/` |
| macOS | `build/macos/Build/Products/Release/latex_to_word_app.app` |
| Linux | `build/linux/x64/release/bundle/` |

Copy the entire output directory (not just the `.exe`) — it includes required DLLs and assets.

---

## Run in development

```sh
flutter run -d windows   # or macos / linux
```

---

## First-launch pandoc setup

On the very first run the app checks for pandoc. If it is not found it shows a one-time setup screen:

1. Click **Download pandoc**.
2. The app fetches the latest release from GitHub Releases (~35 MB), extracts the binary, and stores it in your OS application support directory:
   - **Windows** `%APPDATA%\latex_to_word_app\pandoc\pandoc.exe`
   - **macOS** `~/Library/Application Support/latex_to_word_app/pandoc/pandoc`
   - **Linux** `~/.local/share/latex_to_word_app/pandoc/pandoc`
3. Subsequent launches skip this step entirely.

### Optional: bundle pandoc for offline / enterprise use

If you need the binary baked into the distribution (no internet required), download it manually before building:

```powershell
# Windows
.\scripts\download_pandoc.ps1
```

```sh
# macOS / Linux
./scripts/download_pandoc.sh
```

Place the downloaded binary at `pandoc/<platform>/pandoc[.exe]`. The CMake build scripts pick it up automatically and place it at `data/pandoc/` next to the executable.

---

## Running tests

```sh
dart test test/extractor_test.dart
```

---

## Project structure

```
lib/
  main.dart                    # App entry point
  converter_state.dart         # ChangeNotifier state (pandoc + conversion)
  screens/
    converter_screen.dart      # Single-screen UI
  widgets/
    drop_zone.dart             # Drag-and-drop wrapper
  services/
    pandoc_resolver.dart       # Resolves bundled / downloaded / PATH binary
    pandoc_downloader.dart     # Downloads pandoc from GitHub Releases
    extractor.dart             # ZIP extraction + main.tex detection
    converter.dart             # pandoc subprocess invocation
    pipeline.dart              # Orchestrates extract ? convert
pandoc/                        # Optional pre-bundled binaries (git-ignored)
  windows/pandoc.exe
  macos/pandoc
  linux/pandoc
scripts/
  download_pandoc.ps1          # Windows helper
  download_pandoc.sh           # macOS / Linux helper
test/
  extractor_test.dart
```
