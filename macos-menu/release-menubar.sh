#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# OCA mDNS Gateway — release the macOS menu-bar app
# (build, verify, optional notarize + staple, publish to dist/).
#
#   ./macos-menu/release-menubar.sh
#   ./macos-menu/release-menubar.sh --clean
#   ./macos-menu/release-menubar.sh --clean --notarize
#   ./macos-menu/release-menubar.sh --notarize \
#     CODE_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" \
#     DEVELOPMENT_TEAM=<TEAMID>
#
# Credentials (optional): put Developer ID vars in repo-root `.env.local`
# (gitignored). See `.env.local.example`. CLI KEY=VALUE overrides the file.
#
# See macos-menu/HOWTO-DISTRIBUTE.md
#-----------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="OCA mDNS Gateway.app"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/macos-menu/.derivedData}"
APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
DIST_DIR="$ROOT/dist"
DIST_APP="$DIST_DIR/$APP_NAME"
DIST_ZIP="$DIST_DIR/${APP_NAME}.zip"

NOTARIZE=0
CLEAN=0

# Optional local release credentials (never commit .env.local).
if [ -f "$ROOT/.env.local" ]; then
  echo "[oca-mdns-gateway] Loading $ROOT/.env.local"
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env.local"
  set +a
fi

# Defaults from env / .env.local; KEY=VALUE args below override.
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-de.deuso.ocamdnsgateway}"
CONFIG="${CONFIG:-Release}"

usage() {
  echo "usage: $0 [--clean] [--notarize] [KEY=VALUE ...]"
  echo ""
  echo "Loads repo-root .env.local if present (CODE_SIGN_IDENTITY, DEVELOPMENT_TEAM, ...)."
  echo ""
  echo "Flags:"
  echo "  --clean      make distclean before build"
  echo "  --notarize   submit to notarytool, staple, then publish"
  echo "  -h/--help    this help"
  echo ""
  echo "KEY=VALUE (overrides .env.local):"
  echo "  CONFIG=Release|Debug"
  echo "  CODE_SIGN_IDENTITY=\"Developer ID Application: <Name> (<TEAMID>)\""
  echo "  DEVELOPMENT_TEAM=<TEAMID>"
  echo "  CODE_SIGN_STYLE=Manual|Automatic"
  echo "  NOTARY_PROFILE=<keychain-profile>   (default: de.deuso.ocamdnsgateway)"
  echo ""
  echo "  make list-identities   # or: security find-identity -v -p codesigning"
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --notarize) NOTARIZE=1 ;;
    --notorize|--notarize=*|--notary*)
      echo "[oca-mdns-gateway] ERROR: unknown option '$arg' (did you mean --notarize?)" >&2
      exit 1
      ;;
    --clean|-c) CLEAN=1 ;;
    -h|--help) usage ;;
    --*)
      echo "[oca-mdns-gateway] ERROR: unknown option '$arg'" >&2
      echo "         Supported flags: --clean, --notarize, -h/--help" >&2
      exit 1
      ;;
    CONFIG=*|CODE_SIGN_IDENTITY=*|DEVELOPMENT_TEAM=*|CODE_SIGN_STYLE=*|NOTARY_PROFILE=*)
      key="${arg%%=*}"
      val="${arg#*=}"
      case "$key" in
        CONFIG) CONFIG="$val" ;;
        CODE_SIGN_IDENTITY) CODE_SIGN_IDENTITY="$val" ;;
        DEVELOPMENT_TEAM) DEVELOPMENT_TEAM="$val" ;;
        CODE_SIGN_STYLE) CODE_SIGN_STYLE="$val" ;;
        NOTARY_PROFILE) NOTARY_PROFILE="$val" ;;
      esac
      ;;
    *=*)
      echo "[oca-mdns-gateway] ERROR: unknown option '$arg' (supported: CONFIG, CODE_SIGN_IDENTITY, DEVELOPMENT_TEAM, CODE_SIGN_STYLE, NOTARY_PROFILE)" >&2
      exit 1
      ;;
    *)
      echo "[oca-mdns-gateway] ERROR: unexpected argument '$arg'" >&2
      usage
      ;;
  esac
done

case "$CONFIG" in
  Release|Debug) ;;
  *)
    echo "[oca-mdns-gateway] ERROR: CONFIG must be Release or Debug (got '$CONFIG')" >&2
    exit 1
    ;;
esac

# Rebuild APP path if CONFIG is Debug (products live under Debug/).
APP="$DERIVED_DATA/Build/Products/$CONFIG/$APP_NAME"

export CODE_SIGN_IDENTITY DEVELOPMENT_TEAM CODE_SIGN_STYLE NOTARY_PROFILE

if [ "$NOTARIZE" = 1 ] && [ "$CODE_SIGN_IDENTITY" = "-" ]; then
  echo "[oca-mdns-gateway] ERROR: --notarize needs CODE_SIGN_IDENTITY='Developer ID Application: ...'" >&2
  echo "         Set it in .env.local or pass CODE_SIGN_IDENTITY=..." >&2
  exit 1
fi

MAKE_ARGS=(menu "CONFIG=$CONFIG" "DERIVED_DATA=$DERIVED_DATA")
if [ "$CODE_SIGN_IDENTITY" != "-" ]; then
  MAKE_ARGS+=("CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY")
fi
[ -n "$DEVELOPMENT_TEAM" ] && MAKE_ARGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
[ -n "$CODE_SIGN_STYLE" ] && MAKE_ARGS+=("CODE_SIGN_STYLE=$CODE_SIGN_STYLE")

cd "$ROOT"

if [ "$CLEAN" = 1 ]; then
  echo "[oca-mdns-gateway] make distclean ..."
  make distclean "CONFIG=$CONFIG" "DERIVED_DATA=$DERIVED_DATA"
fi

echo "[oca-mdns-gateway] Release build - identity: $CODE_SIGN_IDENTITY"
make "${MAKE_ARGS[@]}"

if [ ! -d "$APP" ]; then
  echo "[oca-mdns-gateway] ERROR: app not found after build: $APP" >&2
  exit 1
fi

echo "[oca-mdns-gateway] Verifying signature on $APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier|Signed Time' || true

publish_to_dist() {
  local src="$1"
  mkdir -p "$DIST_DIR"
  rm -rf "$DIST_APP" "$DIST_ZIP"
  cp -R "$src" "$DIST_APP"
  xattr -cr "$DIST_APP" 2>/dev/null || true
  echo "[oca-mdns-gateway] Dist app -> $DIST_APP"
  ditto -c -k --keepParent "$DIST_APP" "$DIST_ZIP"
  echo "[oca-mdns-gateway] Dist zip -> $DIST_ZIP"
}

if [ "$NOTARIZE" = 1 ]; then
  STAGE_DIR="$(mktemp -d /tmp/oca-mdns-gateway-notarize.XXXXXX)"
  ZIP="$STAGE_DIR/${APP_NAME}.zip"
  echo "[oca-mdns-gateway] Zip for notarytool -> $ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"

  echo "[oca-mdns-gateway] notarytool submit (profile: $NOTARY_PROFILE) ..."
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "[oca-mdns-gateway] Staple ..."
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl -a -vv --type install "$APP" || true

  publish_to_dist "$APP"
  rm -rf "$STAGE_DIR"
  echo "[oca-mdns-gateway] Notarized + stapled + published to dist/."
else
  echo "[oca-mdns-gateway] Notarize skipped (add --notarize for distribution)."
  publish_to_dist "$APP"
fi

echo "[oca-mdns-gateway] Product: $APP"
echo "[oca-mdns-gateway] Dist:    $DIST_APP"
echo "[oca-mdns-gateway] Zip:     $DIST_ZIP"
open -R "$DIST_APP" 2>/dev/null || open -R "$APP" 2>/dev/null || true
