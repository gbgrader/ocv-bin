#!/usr/bin/env bash
# Links smoke/ (a small gocv program) against <out-dir> using cgo-ldflags.txt, the same way
# gbgrader/MarkIt consumes the archive, runs it, and checks that the binary doesn't depend on any
# OpenCV or compiler runtime shared library.
#
# Usage: ./smoke.sh <out-dir>

set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"
prefix="$(cd "${1:?usage: smoke.sh <out-dir>}" && { pwd -W 2>/dev/null || pwd; })"
ocv_version="$(cut -d- -f1 "$repo_dir/VERSION")"

export GOFLAGS="-tags=customenv"
export CGO_ENABLED=1
export CGO_CPPFLAGS="-I$prefix/include/opencv4"
CGO_LDFLAGS="$(sed "s|@PREFIX@|$prefix|g" "$prefix/cgo-ldflags.txt")"
export CGO_LDFLAGS

cd "$repo_dir/smoke"
exe=smoke
[[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]] && exe=smoke.exe
go build -o "$exe" .
"./$exe" "$ocv_version"

# Any libjpeg symbol would clash with the libjpeg MuPDF bundles (see WITH_JPEG in build.sh).
if nm --defined-only -g "$prefix"/lib/*.a "$prefix"/lib/opencv4/3rdparty/*.a 2>/dev/null | grep -E ' _?jpeg_' >/dev/null; then
  echo "the archives define libjpeg symbols, which clash with MuPDF's libjpeg" >&2
  exit 1
fi

# Allowlist rather than denylist: anything that isn't part of the OS or the C/C++ runtime means the
# build picked up a library from the build machine, which the users' machines won't have.
echo "shared library dependencies:"
bad=()
case "$(uname -s)" in
Linux)
  ldd "$exe"
  for lib in $(ldd "$exe" | awk '{print $1}'); do
    [[ "$lib" =~ ^(linux-vdso|/lib64/ld-linux|ld-linux|lib(c|m|dl|rt|pthread|resolv|stdc\+\+|gcc_s)\.so) ]] || bad+=("$lib")
  done
  ;;
Darwin)
  otool -L "$exe"
  for lib in $(otool -L "$exe" | tail -n +2 | awk '{print $1}'); do
    [[ "$lib" =~ ^(/usr/lib/|/System/Library/) ]] || bad+=("$lib")
  done
  ;;
*)
  objdump -p "$exe" | grep 'DLL Name'
  for dll in $(objdump -p "$exe" | awk '/DLL Name/ {print $3}'); do
    [[ "$dll" =~ ^api-ms-win- || -f "/c/Windows/System32/$dll" ]] || bad+=("$dll")
  done
  ;;
esac
if ((${#bad[@]})); then
  echo "binary depends on libraries that aren't part of the OS: ${bad[*]}" >&2
  exit 1
fi
