# ocv-bin

Prebuilt **static** [OpenCV](https://opencv.org/) libraries for linking [gocv](https://gocv.io/) into
gbgrader projects (MarkIt). Programs linked against them don't need OpenCV installed at runtime.

Each [release](https://github.com/gbgrader/ocv-bin/releases) has one archive per platform:

| Asset | Built on | Toolchain |
|---|---|---|
| `ocv-bin-<version>-linux-x64.tar.gz` | Ubuntu 22.04 (glibc 2.35) | system gcc |
| `ocv-bin-<version>-macos-arm64.tar.gz` | macOS (deployment target 13.0) | Apple clang |
| `ocv-bin-<version>-windows-x64.zip` | Windows | [WinLibs](https://winlibs.com/) gcc, UCRT (pinned in `mise.windows.toml`) |

On Windows, link with the **same** WinLibs release (MarkIt pins it in its own `mise.windows.toml`).
Static libraries built for one MinGW C runtime (UCRT vs. msvcrt) or gcc version can fail to link with another.

## Versions

Tags look like `4.13.0-1`: the OpenCV version, then a build number. The build number goes up when the
build changes (cmake flags, toolchain) but OpenCV doesn't. The `VERSION` file holds the version being
built, and CI refuses a tag that doesn't match it.

## What's in an archive

```
include/opencv4/          headers
lib/                      libopencv_*.a
lib/opencv4/3rdparty/     bundled dependencies (libpng, zlib, protobuf, ...)
lib/pkgconfig/opencv4.pc  pkg-config file, relocatable (prefix=${pcfiledir}/../..)
share/licenses/opencv4/   licenses of the bundled dependencies (keep these when redistributing)
cgo-ldflags.txt           all linker flags for a static link, with @PREFIX@ for the extraction directory
```

Only the modules gocv's main package uses are built: core, imgproc, imgcodecs, highgui, videoio, video,
objdetect, features2d, calib3d, dnn, photo and their dependencies. There's no contrib, no GUI or
camera/video backends, and no TBB. The image codecs are bundled.

## Using it

With gocv's `customenv` build tag (which turns off gocv's built-in flags), set:

```sh
GOFLAGS=-tags=customenv
CGO_CPPFLAGS="-I<prefix>/include/opencv4"
CGO_LDFLAGS="<contents of cgo-ldflags.txt, with @PREFIX@ replaced by <prefix>>"
```

`cgo-ldflags.txt` is the output of `pkg-config --static --libs opencv4` plus fixes, so you don't need
pkg-config installed:

- On Windows it adds `comdlg32`, `oleaut32` and `uuid`, which OpenCV's MinGW `.pc` file leaves out.
  These are also added to the `.pc` file.
- On Windows it adds `-static`, which also links libstdc++, libgcc and winpthread statically.

With mise, the archive installs like a tool:

```toml
[tools]
"github:gbgrader/ocv-bin" = "4.13.0-1"

[env]
GOFLAGS = "-tags=customenv"
CGO_CPPFLAGS = { value = "-I{{ tools['github:gbgrader/ocv-bin'].path }}/include/opencv4", tools = true }
CGO_LDFLAGS = { value = "{{ read_file(path=tools['github:gbgrader/ocv-bin'].path ~ '/cgo-ldflags.txt') | trim | replace(from='@PREFIX@', to=tools['github:gbgrader/ocv-bin'].path) }}", tools = true }
```

## Building

CI builds every push and pull request. Each platform job builds OpenCV, then links and runs
`smoke/` (a small gocv program) against the result. It also checks that the binary doesn't depend on
OpenCV or compiler runtime shared libraries.

To build locally, on the platform you want archives for (on Windows, use Git Bash):

```sh
mise install
mise x -- ./build.sh out
mise x -- ./smoke.sh out
```

## Releasing

1. Update `VERSION` (and `smoke/go.mod`'s gocv version if the OpenCV version changed) and merge to `main`.
2. Tag the merge commit with the same version and push the tag: `git tag 4.13.0-1 && git push origin 4.13.0-1`.
3. CI builds all platforms and publishes a release with the archives and a `SHA256SUMS` file.
