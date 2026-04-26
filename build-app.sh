#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# build-app.sh — Build Browse as a properly packaged .app bundle
#
# Produces a code-signed macOS .app bundle from the SPM executable
# so that WebKit's multi-process helpers (WebContent, Networking)
# can validate the host via XPC and start without sandbox errors.
#
# Usage:
#   ./build-app.sh              # build release .app
#   ./build-app.sh --run        # build and launch
#   ./build-app.sh --debug      # build debug .app
#   ./build-app.sh --debug --run
# ─────────────────────────────────────────────────────────────

APP_NAME="Browse"
BUNDLE_ID="com.browse.app"
CONFIGURATION="release"
RUN_AFTER_BUILD=false

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --run)   RUN_AFTER_BUILD=true ;;
        --debug) CONFIGURATION="debug" ;;
        *)       echo "Unknown option: $arg"; exit 1 ;;
    esac
done

BUILD_DIR=".build/$CONFIGURATION"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFO_PLIST="$SCRIPT_DIR/Browse/Sources/Resources/Info.plist"
ENTITLEMENTS="$SCRIPT_DIR/Browse.entitlements"

# ── Pre-flight checks ───────────────────────────────────────
echo "==> Pre-flight checks"

if [ ! -f "$INFO_PLIST" ]; then
    echo "ERROR: Info.plist not found at $INFO_PLIST"
    exit 1
fi

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "ERROR: Entitlements file not found at $ENTITLEMENTS"
    exit 1
fi

# Verify Info.plist has no entitlement keys (common mistake)
if grep -q "com.apple.security" "$INFO_PLIST"; then
    echo "ERROR: Info.plist contains entitlement keys (com.apple.security.*)."
    echo "       Entitlements belong in Browse.entitlements, not Info.plist."
    exit 1
fi

echo "    Info.plist:    OK"
echo "    Entitlements:  OK"

# ── Build ────────────────────────────────────────────────────
echo ""
echo "==> Building $APP_NAME ($CONFIGURATION)..."
swift build -c "$CONFIGURATION"

# ── Assemble .app bundle ────────────────────────────────────
echo ""
echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the compiled executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy the canonical Info.plist (single source of truth)
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

# Write PkgInfo (standard for APPL bundles; helps Finder/LaunchServices identify the bundle type)
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# ── Code signing ────────────────────────────────────────────
echo ""
SIGNING_IDENTITY="${BROWSE_SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)"
fi

if [ -n "$SIGNING_IDENTITY" ] && security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
    echo "==> Code-signing with identity: $SIGNING_IDENTITY"
else
    if [ -n "$SIGNING_IDENTITY" ]; then
        echo "WARNING: Signing identity not found: $SIGNING_IDENTITY"
    else
        echo "WARNING: No Apple Development signing identity found."
    fi
    echo "         Falling back to ad-hoc signing."
    SIGNING_IDENTITY="-"
fi

codesign --sign "$SIGNING_IDENTITY" \
         --force \
         --entitlements "$ENTITLEMENTS" \
         --generate-entitlement-der \
         "$APP_BUNDLE"

# Verify the signature
echo ""
echo "==> Verifying signature..."
codesign --verify --verbose=2 "$APP_BUNDLE" 2>&1 || {
    echo "WARNING: Signature verification reported issues (may be okay for ad-hoc)"
}

# Show the entitlements that were embedded
echo ""
echo "==> Embedded entitlements:"
codesign --display --entitlements - "$APP_BUNDLE" 2>/dev/null || true

# ── Summary ─────────────────────────────────────────────────
echo ""
echo "==> Done!"
echo "    Bundle:     $APP_BUNDLE"
echo "    Bundle ID:  $BUNDLE_ID"
echo ""
echo "    Run with:   open $APP_BUNDLE"
echo "    Logs with:  log stream --predicate 'subsystem == \"com.browse.app\" OR process == \"Browse\"' --level debug"

# ── Optional: launch ────────────────────────────────────────
if [ "$RUN_AFTER_BUILD" = true ]; then
    echo ""
    echo "==> Launching $APP_NAME..."
    open "$APP_BUNDLE"
fi
