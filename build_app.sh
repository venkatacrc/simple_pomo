#!/usr/bin/env bash
# Build SimplePomo as a proper macOS .app bundle.
# Usage: ./build_app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="SimplePomo"
BUNDLE_ID="com.simplepomo.app"
DISPLAY_NAME="Simple Pomo"
VERSION="1.0.0"
BUILD_NUM="1"

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="${ROOT}/build/${APP_NAME}.app"

echo "→ Building SimplePomo (${CONFIG})"
swift build -c "${CONFIG}"
BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)"
EXEC="${BIN_PATH}/${APP_NAME}"

if [[ ! -x "${EXEC}" ]]; then
  echo "✗ Executable not found at ${EXEC}" >&2
  exit 1
fi

echo "→ Assembling app bundle at ${APP_ROOT}"
rm -rf "${APP_ROOT}"
mkdir -p "${APP_ROOT}/Contents/MacOS"
mkdir -p "${APP_ROOT}/Contents/Resources"
cp "${EXEC}" "${APP_ROOT}/Contents/MacOS/${APP_NAME}"

cat > "${APP_ROOT}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>      <string>en</string>
    <key>CFBundleDisplayName</key>            <string>${DISPLAY_NAME}</string>
    <key>CFBundleExecutable</key>             <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>             <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>  <string>6.0</string>
    <key>CFBundleName</key>                   <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>            <string>APPL</string>
    <key>CFBundleShortVersionString</key>     <string>${VERSION}</string>
    <key>CFBundleVersion</key>                <string>${BUILD_NUM}</string>
    <key>LSMinimumSystemVersion</key>         <string>14.0</string>
    <key>LSApplicationCategoryType</key>      <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>        <true/>
    <key>NSPrincipalClass</key>               <string>NSApplication</string>
    <key>NSUserNotificationAlertStyle</key>   <string>banner</string>
    <key>CFBundleIconFile</key>               <string>AppIcon</string>
</dict>
</plist>
PLIST

# Generate a simple app icon (.icns) by rendering an AppKit-drawn PNG at 1024px
# and resampling via `sips`.
if command -v iconutil >/dev/null 2>&1 && command -v sips >/dev/null 2>&1; then
    echo "→ Rendering app icon"
    TMP_DIR="$(mktemp -d)"
    ICONSET_DIR="${TMP_DIR}/AppIcon.iconset"
    mkdir -p "${ICONSET_DIR}"
    SRC_PNG="${TMP_DIR}/icon-1024.png"
    SWIFT_SRC="${TMP_DIR}/make_icon.swift"

    cat > "${SWIFT_SRC}" <<'SWIFT'
import AppKit
import CoreGraphics

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { exit(1) }

let rect = CGRect(x: 0, y: 0, width: size, height: size)
let corner: CGFloat = CGFloat(size) * 0.22

// Rounded-rect background gradient
let bgPath = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()
let colors = [
    CGColor(red: 0.88, green: 0.32, blue: 0.32, alpha: 1),
    CGColor(red: 0.62, green: 0.18, blue: 0.18, alpha: 1)
] as CFArray
if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: 0, y: CGFloat(size)),
                           end: CGPoint(x: CGFloat(size), y: 0),
                           options: [])
}
ctx.restoreGState()

// Tomato body
let pad: CGFloat = CGFloat(size) * 0.18
let body = CGRect(x: pad, y: pad * 0.85,
                  width: CGFloat(size) - pad * 2,
                  height: CGFloat(size) - pad * 1.9)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.addEllipse(in: body); ctx.fillPath()

// Subtle inner shadow band
ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.85, alpha: 0.45))
let highlight = CGRect(x: body.minX + body.width * 0.15,
                       y: body.maxY - body.height * 0.40,
                       width: body.width * 0.55,
                       height: body.height * 0.22)
ctx.addEllipse(in: highlight); ctx.fillPath()

// Stem
let stemRect = CGRect(x: CGFloat(size)/2 - CGFloat(size)*0.03,
                      y: body.maxY - CGFloat(size)*0.02,
                      width: CGFloat(size)*0.06,
                      height: CGFloat(size)*0.10)
ctx.setFillColor(CGColor(red: 0.18, green: 0.45, blue: 0.25, alpha: 1))
ctx.fill(stemRect)

// Leaf
ctx.saveGState()
ctx.translateBy(x: CGFloat(size)/2 + CGFloat(size)*0.04,
                y: body.maxY + CGFloat(size)*0.02)
ctx.rotate(by: -0.5)
let leaf = CGRect(x: 0, y: 0, width: CGFloat(size)*0.22, height: CGFloat(size)*0.10)
ctx.setFillColor(CGColor(red: 0.28, green: 0.66, blue: 0.36, alpha: 1))
ctx.addEllipse(in: leaf); ctx.fillPath()
ctx.restoreGState()

guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
try? png.write(to: outURL)
SWIFT

    swift "${SWIFT_SRC}" "${SRC_PNG}" >/dev/null 2>&1 || true

    if [[ -s "${SRC_PNG}" ]]; then
        for spec in "16:1" "16:2" "32:1" "32:2" "128:1" "128:2" "256:1" "256:2" "512:1" "512:2"; do
            px="${spec%:*}"; scale="${spec##*:}"
            out_px=$(( px * scale ))
            suffix=""
            [[ "${scale}" == "2" ]] && suffix="@2x"
            sips -z "${out_px}" "${out_px}" "${SRC_PNG}" \
                 --out "${ICONSET_DIR}/icon_${px}x${px}${suffix}.png" >/dev/null 2>&1 || true
        done
        iconutil -c icns "${ICONSET_DIR}" -o "${APP_ROOT}/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    fi
fi

echo "✓ Built ${APP_ROOT}"
echo "  Run with:   open '${APP_ROOT}'"
echo "  Move with:  cp -R '${APP_ROOT}' /Applications/"
