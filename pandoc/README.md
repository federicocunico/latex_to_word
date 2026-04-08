# Pandoc Binaries

Place the platform-specific pandoc binaries here before building a release.

## Directory structure

```
pandoc/
  windows/
    pandoc.exe        ← Windows x86_64
  macos/
    pandoc            ← macOS universal / arm64
  linux/
    pandoc            ← Linux x86_64
```

## How to download

Go to the [pandoc releases page](https://github.com/jgm/pandoc/releases/latest)
and download the appropriate package for each platform:

| Platform | Package type | File to extract |
|----------|-------------|-----------------|
| Windows  | `pandoc-*-windows-x86_64.zip` | `pandoc.exe` |
| macOS    | `pandoc-*-x86_64-macOS.zip` or arm64 variant | `bin/pandoc` |
| Linux    | `pandoc-*-linux-amd64.tar.gz` | `bin/pandoc` |

## Why not bundled in git?

The pandoc binary is ~100 MB and platform-specific, making it unsuitable for
version control. Use a CI step or a local `scripts/download_pandoc.ps1`
(Windows) / `scripts/download_pandoc.sh` (macOS/Linux) to fetch the binary
automatically before building.

## Runtime resolution

At runtime, `PandocResolver` looks for the binary at:

```
<exe_dir>/data/pandoc/pandoc[.exe]
```

The CMake / packaging build scripts copy the binary from this directory into
the correct location automatically.
