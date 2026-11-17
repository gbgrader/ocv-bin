#!/usr/bin/env bash
# Builds OpenCV as static libraries for the current platform (Linux, macOS, or Windows via Git Bash
# with the WinLibs gcc from mise.windows.toml) and installs it into <out-dir>:
#
#   include/opencv4/          headers
#   lib/                      libopencv_*.a
#   lib/opencv4/3rdparty/     bundled dependencies (libpng, zlib, ...)
#   lib/pkgconfig/opencv4.pc  relocatable pkg-config file
#   share/licenses/opencv4/   licenses of OpenCV's bundled dependencies
#   cgo-ldflags.txt           every linker flag a static link needs, with @PREFIX@ standing for the
#                             directory the archive gets extracted to
#
# Usage: ./build.sh <out-dir>   (the OpenCV version comes from the VERSION file)

set -euo pipefail

out="${1:?usage: build.sh <out-dir>}"
repo_dir="$(cd "$(dirname "$0")" && pwd)"
ocv_version="$(cut -d- -f1 "$repo_dir/VERSION")"

case "$(uname -s)" in
Linux) platform=linux ;;
Darwin) platform=macos ;;
MINGW* | MSYS*) platform=windows ;;
*)
  echo "unsupported platform: $(uname -s)" >&2
  exit 1
  ;;
esac

# Native Windows programs (cmake, gcc) need C:/... paths, not Git Bash's /c/... ones.
abspath() { (cd "$1" && { pwd -W 2>/dev/null || pwd; }); }

mkdir -p "$out" "$repo_dir/.work/src" "$repo_dir/.work/build"
out="$(abspath "$out")"
src="$(abspath "$repo_dir/.work/src")"
build="$(abspath "$repo_dir/.work/build")"

if [[ ! -f "$src/CMakeLists.txt" ]]; then
  curl -fsSL "https://github.com/opencv/opencv/archive/refs/tags/${ocv_version}.tar.gz" |
    tar -xz -C "$src" --strip-components=1
fi

flags=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$out"
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DBUILD_SHARED_LIBS=OFF
  -DOPENCV_GENERATE_PKGCONFIG=ON
  # Only the modules gocv's main package binds (plus their dependencies, which cmake adds itself).
  -DBUILD_LIST=core,imgproc,imgcodecs,highgui,videoio,video,objdetect,features2d,calib3d,dnn,photo
  -DBUILD_DOCS=OFF
  -DBUILD_EXAMPLES=OFF
  -DBUILD_TESTS=OFF
  -DBUILD_PERF_TESTS=OFF
  -DBUILD_opencv_apps=OFF
  -DBUILD_JAVA=OFF
  -DBUILD_opencv_python2=OFF
  -DBUILD_opencv_python3=OFF
  # Bundle the codecs instead of linking whatever the build machine has installed.
  -DBUILD_ZLIB=ON
  -DBUILD_PNG=ON
  -DBUILD_JPEG=ON
  -DBUILD_TIFF=ON
  -DBUILD_WEBP=ON
  -DBUILD_OPENJPEG=ON
  -DWITH_JASPER=OFF
  -DWITH_OPENEXR=OFF
  -DWITH_AVIF=OFF
  -DWITH_JPEGXL=OFF
  # Optional system libraries OpenCV links if it happens to find them on the build machine. They're
  # all off so every runner (and every local build) produces the same, self-contained libraries.
  -DWITH_EIGEN=OFF
  -DWITH_LAPACK=OFF
  -DWITH_VTK=OFF
  -DWITH_CUDA=OFF
  -DWITH_NVCUVID=OFF
  -DWITH_NVCUVENC=OFF
  -DWITH_OPENVINO=OFF
  -DWITH_OPENCLAMDBLAS=OFF
  -DWITH_OPENCLAMDFFT=OFF
  -DWITH_DIRECTX=OFF
  -DWITH_DIRECTML=OFF
  -DWITH_OPENCL_D3D11_NV=OFF
  -DWITH_GDAL=OFF
  -DWITH_GPHOTO2=OFF
  # No video/camera/GUI backends: they pull in system libraries we'd have to link (or ship).
  -DWITH_FFMPEG=OFF
  -DWITH_GSTREAMER=OFF
  -DWITH_V4L=OFF
  -DWITH_1394=OFF
  -DWITH_AVFOUNDATION=OFF
  -DWITH_MSMF=OFF
  -DWITH_DSHOW=OFF
  -DWITH_OBSENSOR=OFF
  -DWITH_GTK=OFF
  -DWITH_QT=OFF
  -DWITH_WIN32UI=OFF
  -DWITH_WAYLAND=OFF
  -DWITH_FRAMEBUFFER=OFF
  -DWITH_VA=OFF
  -DWITH_TBB=OFF
  # Same layout on every platform (Windows would otherwise use x64/mingw/staticlib/...).
  -DOPENCV_BIN_INSTALL_PATH=bin
  -DOPENCV_LIB_INSTALL_PATH=lib
  -DOPENCV_LIB_ARCHIVE_INSTALL_PATH=lib
  -DOPENCV_3P_LIB_INSTALL_PATH=lib/opencv4/3rdparty
  -DOPENCV_CONFIG_INSTALL_PATH=lib/cmake/opencv4
  -DOPENCV_INCLUDE_INSTALL_PATH=include/opencv4
  -DOPENCV_OTHER_INSTALL_PATH=share/opencv4
  -DOPENCV_LICENSES_INSTALL_PATH=share/licenses/opencv4
)

extra_ldflags=""
case "$platform" in
macos)
  flags+=(-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0)
  ;;
windows)
  # Use mise's WinLibs gcc explicitly: the runner also has an older msvcrt MinGW and MSVC installed.
  cc="$(mise which gcc)"
  cxx="$(mise which g++)"
  flags+=(-DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx")
  # -static also bundles libstdc++, libgcc and winpthread, so the final .exe only needs DLLs that
  # ship with Windows.
  extra_ldflags="-static"
  ;;
esac

cmake -S "$src" -B "$build" "${flags[@]}"
cmake --build "$build"
cmake --install "$build"

pc="$out/lib/pkgconfig/opencv4.pc"

# Make the .pc file relative to its own location so the archive can be extracted anywhere.
perl -pi -e 's|^prefix=.*|prefix=\${pcfiledir}/../..|' "$pc"

# OpenCV's MinGW .pc file leaves out these system libraries, which highgui and videoio use.
if [[ "$platform" == windows ]]; then
  perl -pi -e 's|^(Libs\.private:.*)$|$1 -lcomdlg32 -loleaut32 -luuid|' "$pc"
fi

# Expand Libs + Libs.private (what `pkg-config --static --libs` prints) with @PREFIX@ as the prefix,
# so consumers don't need pkg-config installed.
perl -e '
  my %var = (prefix => "\@PREFIX\@");
  my %field;
  while (<>) {
    chomp;
    if (/^(\w+)=(.*)$/) { $var{$1} //= $2 }
    elsif (/^([\w.]+):\s*(.*)$/) { $field{$1} = $2 }
  }
  my $s = "$field{Libs} $field{q(Libs.private)}";
  1 while $s =~ s/\$\{(\w+)\}/$var{$1}/g;
  print "$s\n";
' "$pc" | sed "s|\$| $extra_ldflags|; s| *\$||" >"$out/cgo-ldflags.txt"

echo "installed OpenCV $ocv_version into $out"
cat "$out/cgo-ldflags.txt"
