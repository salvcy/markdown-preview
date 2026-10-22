#!/bin/bash
# Builds "Markdown Preview.app" (an empty container app plus a Quick Look
# extension), installs it in /Applications and registers it with Quick Look.
#
#   ./build.sh             build + install
#   ./build.sh uninstall   remove it again
#
# Signing: ad-hoc by default. Set SIGN_IDENTITY to use a certificate, e.g.
#   SIGN_IDENTITY="Apple Development" ./build.sh
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"

NAME="Markdown Preview"
EXT_ID="local.MarkdownPreview.QuickLook"
DEST="/Applications/$NAME.app"
DEST_EXT="$DEST/Contents/PlugIns/MarkdownPreview.appex"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Paths of every copy of the extension the system has registered.
registered_paths() {
  { pluginkit -m -A -D -v -i "$EXT_ID" 2>/dev/null || true; } | awk -F'\t' 'NF >= 4 { print $NF }'
}

is_registered() {
  local paths
  paths="$(registered_paths)"
  grep -qxF "$DEST_EXT" <<<"$paths"
}

# Waits up to 10 s until the installed extension is (yes) or no copy at all is (no) registered.
wait_for_registration() {
  for _ in $(seq 1 20); do
    if [ "$1" = yes ]; then
      is_registered && return 0
    else
      [ -z "$(registered_paths)" ] && return 0
    fi
    sleep 0.5
  done
  return 1
}

reset_quicklook() {
  qlmanage -r >/dev/null 2>&1 || true
  qlmanage -r cache >/dev/null 2>&1 || true
}

# Removes the installed app and every registration of the extension, including
# stale ones (e.g. from older versions of this script that built inside the project).
unregister_all() {
  pkill -f "MarkdownPreview.appex/Contents/MacOS/MarkdownPreview" 2>/dev/null || true
  while IFS= read -r path; do
    pluginkit -r "$path" 2>/dev/null || true
  done < <(registered_paths)
  for app in "$DEST" "$ROOT/build/$NAME.app"; do
    "$LSREGISTER" -u "$app" 2>/dev/null || true
  done
  rm -rf "$DEST" "$ROOT/build"
  # Let the system finish removing it before anything new is registered.
  wait_for_registration no || echo "warning: the system still lists an old copy of the extension" >&2
}

# Unregisters copies of the extension other than the installed one (e.g. from a moved
# or deleted checkout), then waits until the system has dropped them.
remove_other_copies() {
  local found=no
  while IFS= read -r path; do
    [ "$path" = "$DEST_EXT" ] && continue
    pluginkit -r "$path" 2>/dev/null || true
    "$LSREGISTER" -u "${path%/Contents/PlugIns/*}" 2>/dev/null || true
    found=yes
  done < <(registered_paths)
  [ "$found" = yes ] || return 0
  local others
  for _ in $(seq 1 20); do
    others="$(registered_paths | grep -vxF "$DEST_EXT" || true)"
    [ -z "$others" ] && return 0
    sleep 0.5
  done
}

if [ "${1:-}" = "uninstall" ]; then
  unregister_all
  reset_quicklook
  echo "Removed $DEST"
  exit 0
fi

# Build outside the project, in a ".noindex" folder: Spotlight skips it, so macOS
# never registers this temporary copy as a second extension with the same ID.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/markdown-preview.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage.noindex"
APP="$STAGE/$NAME.app"
EXT="$APP/Contents/PlugIns/MarkdownPreview.appex"
OBJ="$WORK/obj"
mkdir -p "$OBJ" "$EXT/Contents/MacOS" "$APP/Contents/MacOS" "$APP/Contents/Resources"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
CC=(xcrun --sdk macosx clang)
COMMON=(-isysroot "$SDK" -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 -Os -fvisibility=hidden)
CMARK="$ROOT/Vendor/cmark-gfm"
INCLUDES=(-I"$CMARK/src" -I"$CMARK/extensions")

echo "==> Compiling cmark-gfm"
pids=()
for f in "$CMARK"/src/*.c "$CMARK"/extensions/*.c; do
  dir="$(basename "$(dirname "$f")")"
  "${CC[@]}" "${COMMON[@]}" -std=c99 -w -fapplication-extension "${INCLUDES[@]}" \
    -c "$f" -o "$OBJ/${dir}_$(basename "${f%.c}").o" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done

echo "==> Linking Quick Look extension"
"${CC[@]}" "${COMMON[@]}" -fobjc-arc -fapplication-extension -Wall -Wextra -Werror "${INCLUDES[@]}" \
  Sources/Extension/MDRender.m Sources/Extension/MDPreviewProvider.m "$OBJ"/*.o \
  -framework Foundation -framework QuickLookUI -framework UniformTypeIdentifiers \
  -Wl,-e,_NSExtensionMain -Wl,-dead_strip \
  -o "$EXT/Contents/MacOS/MarkdownPreview"
cp Sources/Extension/Info.plist "$EXT/Contents/Info.plist"

echo "==> Linking container app"
"${CC[@]}" "${COMMON[@]}" -fobjc-arc -Wall -Wextra -Werror \
  Sources/App/main.m -framework Cocoa -Wl,-dead_strip \
  -o "$APP/Contents/MacOS/MarkdownPreview"
cp Sources/App/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$CMARK/COPYING" "$APP/Contents/Resources/cmark-gfm-LICENSE.txt"

echo "==> Compiling app icon"
# Assets.car holds the light/dark/tinted icon (macOS 26+); AppIcon.icns covers older systems.
# actool hands the work to a shared background server (ibtoold). That server can get stuck
# returning an old error to every later build, so each attempt starts a fresh one and shuts
# it down afterwards. Paths are absolute because the server has its own working directory.
compile_icon() {
  xcrun actool --quit-all-idle-servers >/dev/null 2>&1 || true
  icon_log="$(xcrun actool "$ROOT/Sources/App/AppIcon.icon" --compile "$APP/Contents/Resources" \
    --platform macosx --target-device mac --minimum-deployment-target 12.0 --app-icon AppIcon \
    --output-partial-info-plist "$WORK/icon-info.plist" --errors --warnings --output-format human-readable-text 2>&1)" || true
  xcrun actool --quit-all-idle-servers >/dev/null 2>&1 || true
  [ -f "$APP/Contents/Resources/Assets.car" ] && [ -f "$APP/Contents/Resources/AppIcon.icns" ]
}
if ! compile_icon; then
  echo "    icon compile failed, retrying"
  sleep 1
  if ! compile_icon; then
    echo "$icon_log" >&2
    echo "error: app icon was not compiled" >&2
    exit 1
  fi
fi

strip -x "$EXT/Contents/MacOS/MarkdownPreview" "$APP/Contents/MacOS/MarkdownPreview"
plutil -lint -s "$EXT/Contents/Info.plist" "$APP/Contents/Info.plist" Sources/Extension/Extension.entitlements

echo "==> Signing (${SIGN_IDENTITY:-ad-hoc})"
IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --options runtime --timestamp=none \
  --entitlements Sources/Extension/Extension.entitlements "$EXT"
codesign --force --sign "$IDENTITY" --options runtime --timestamp=none "$APP"
codesign --verify --strict --deep "$APP"

echo "==> Installing to $DEST"
remove_other_copies
pkill -f "MarkdownPreview.appex/Contents/MacOS/MarkdownPreview" 2>/dev/null || true
if [ -d "$DEST" ]; then
  # Update in place. Deleting the old app first makes macOS unregister the extension in
  # the background, which can undo the new registration a few seconds later.
  rsync -a --checksum --delete "$APP/" "$DEST/"
else
  ditto "$APP" "$DEST"
fi
codesign --verify --strict --deep "$DEST"
rm -rf "$WORK"

# Register, then confirm it is still registered a moment later.
registered=no
for attempt in 1 2 3 4 5; do
  "$LSREGISTER" -f -R "$DEST"
  pluginkit -a "$DEST_EXT"
  pluginkit -e use -i "$EXT_ID"
  if wait_for_registration yes; then
    sleep 2
    if is_registered; then registered=yes; break; fi
  fi
  echo "    waiting for macOS to register the extension ($attempt)"
  sleep 3
done
if [ "$registered" != yes ]; then
  echo "error: macOS did not register the Quick Look extension" >&2
  exit 1
fi
reset_quicklook

echo "Done. Select a .md file in Finder and press Space."
