#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

build_directory="$project_root/.build"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_directory/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$build_directory/ModuleCache"

swift_release() {
    swift build --disable-sandbox --cache-path "$build_directory/cache" --config-path "$build_directory/config" --security-path "$build_directory/security" -c release "$@"
}

swift_release
binary_directory=$(swift_release --show-bin-path)
app_bundle="$project_root/dist/WakeLight.app"
resources="$app_bundle/Contents/Resources"

iconset="$build_directory/AppIcon.iconset"
mkdir -p "$iconset" "$app_bundle/Contents/MacOS" "$resources"
for size in 16 32 128 256 512; do
    double_size=$((size * 2))
    sips -z "$size" "$size" Assets/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$double_size" "$double_size" Assets/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$resources/AppIcon.icns"

cp Packaging/Info.plist "$app_bundle/Contents/Info.plist"
cp "$binary_directory/WakeLight" "$app_bundle/Contents/MacOS/WakeLight"
codesign --force --sign - "$app_bundle"

echo "$app_bundle"
