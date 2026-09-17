#!/bin/bash
# build.sh — Build + IPA pipeline for jellypic
#
# Derived from the vpnold/podcold script, but WITHOUT the Swift-runtime patching
# (no -toolchain, no dylib swap, no vtool version-min, no Metal dylib removal).
# Those steps only ever wrote inside their own app bundle, so dropping them here
# changes nothing for the apps that still use them.
#
# Default target: iOS 12.0 minimum, arm64 only.
#   - iOS 11 dropped 32-bit, so every iOS 12 device is arm64. No fat binary.
#   - Swift ABI ships in the OS since iOS 12.2; below that Xcode embeds the
#     runtime into Frameworks/ by itself. Nothing to patch either way.
#
# Everything is overridable by environment variable so the same script runs on
# SERV2 today (Xcode 13.2.1 / SDK 15.2) and on a modern CI runner later.
# See CLAUDE.md "Legacy plumbing" for what to change as the floor moves.
#
# This repo is the source of truth; SERV2 is only a build slave. Every run
# rsyncs the local project up before compiling, so never edit on SERV2 — those
# changes are invisible to git and will be overwritten.
#
# Credentials are never stored here. BUILD_PASS must come from the environment,
# or from .env.local (gitignored, sourced automatically).
#
# Usage:
#   ./build.sh                                  # sync + build on SERV2 over ssh
#   DEPLOYMENT_TARGET=15.0 ./build.sh           # raise the floor
#   CONFIGURATION=Release ./build.sh            # release build
#   SYNC=0 ./build.sh                           # build what is already on SERV2
#   BUILD_HOST= ./build.sh                      # build locally (CI runner)
#   BUILD_HOST= DEVELOPER_DIR=/Applications/Xcode-26.app/Contents/Developer \
#     DEPLOYMENT_TARGET=12.0 ./build.sh         # local build, pinned Xcode

set -e

# ── Configuration (override via env) ─────────────────────────────────────────
PROJECT_NAME="${PROJECT_NAME:-jellypic}"
SCHEME="${SCHEME:-$PROJECT_NAME}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-12.0}"
ARCHS="${ARCHS:-arm64}"
SDK="${SDK:-iphoneos}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"        # "-" = ad-hoc
DEVELOPER_DIR="${DEVELOPER_DIR:-}"         # empty = whatever xcode-select points at
REMOTE_BASE="${REMOTE_BASE:-}"             # empty = $HOME/Documents/$PROJECT_NAME
OUTPUT_IPA="${OUTPUT_IPA:-$HOME/Desktop/$PROJECT_NAME.ipa}"
SYNC="${SYNC:-1}"                          # 0 = skip the rsync, build SERV2's copy as-is
LOCAL_PROJECT_DIR="${LOCAL_PROJECT_DIR:-$(cd "$(dirname "$0")" && pwd)/$PROJECT_NAME}"

# BUILD_HOST uses ${VAR-default}, not ${VAR:-default}: setting it to the empty
# string is meaningful (= build on this machine, no ssh), unlike leaving it unset.
BUILD_HOST="${BUILD_HOST-srv-admin@192.168.0.101}"   # IP — SERV2.local mDNS hangs
SSH_OPTS="-o IdentitiesOnly=yes -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Credentials come from the environment, never from this file — it is tracked in
# git. .env.local is gitignored and sourced here as a convenience so the password
# stays out of shell history too.
ENV_LOCAL="$(cd "$(dirname "$0")" && pwd)/.env.local"
# shellcheck source=/dev/null
[ -f "$ENV_LOCAL" ] && . "$ENV_LOCAL"

if [ -n "$BUILD_HOST" ] && [ -z "${BUILD_PASS:-}" ]; then
  echo "ERROR: BUILD_PASS is not set." >&2
  echo "       Either:  echo 'BUILD_PASS=…' > $ENV_LOCAL" >&2
  echo "       or:      BUILD_PASS=… ./build.sh" >&2
  echo "       or build locally with:  BUILD_HOST= ./build.sh" >&2
  exit 1
fi

# sshpass reads SSHPASS from the environment. Using -p instead would put the
# password in the process arguments, where any local process can read it via ps.
# The env-var name must be ATTACHED (-eSSHPASS): with a space, sshpass 1.10
# swallows the following argument — "ssh" — and looks for a $ssh variable.
export SSHPASS="${BUILD_PASS:-}"

# ── Remote/local build script ────────────────────────────────────────────────
# The body is a quoted heredoc (no local expansion); the settings above are
# passed in as a generated `export` prologue, %q-escaped.
emit_build_script() {
  printf 'export PROJECT_NAME=%q SCHEME=%q CONFIGURATION=%q DEPLOYMENT_TARGET=%q ARCHS=%q SDK=%q SIGN_IDENTITY=%q REMOTE_BASE=%q DEVELOPER_DIR=%q\n' \
    "$PROJECT_NAME" "$SCHEME" "$CONFIGURATION" "$DEPLOYMENT_TARGET" \
    "$ARCHS" "$SDK" "$SIGN_IDENTITY" "$REMOTE_BASE" "$DEVELOPER_DIR"
  cat <<'BUILD'
set -e
set -o pipefail

# An exported-but-empty DEVELOPER_DIR breaks xcrun; unset it instead.
[ -n "$DEVELOPER_DIR" ] || unset DEVELOPER_DIR

BASE="${REMOTE_BASE:-$HOME/Documents/$PROJECT_NAME}"
PROJECT_DIR="$BASE/$PROJECT_NAME"
DD="$BASE/DerivedData"
IPA_DIR="$BASE/build"
# Products land in "<Configuration>-<platform>"; strip any version digits so
# both "iphoneos" and "iphoneos15.2" resolve to the same directory.
APP="$DD/Build/Products/$CONFIGURATION-${SDK%%[0-9.]*}/$PROJECT_NAME.app"
FWDIR="$APP/Frameworks"

# ── 1. Preflight ────────────────────────────────────────────────────────────
echo "[1/4] Preflight..."
if [ ! -d "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" ]; then
  echo "ERROR: $PROJECT_DIR/$PROJECT_NAME.xcodeproj not found."
  echo "       Create the Xcode project there first."
  exit 1
fi
echo "      $(xcodebuild -version | head -1) / SDK $(xcrun --sdk "$SDK" --show-sdk-version)"
echo "      min iOS $DEPLOYMENT_TARGET | archs $ARCHS | $CONFIGURATION"

# ── 2. Build ────────────────────────────────────────────────────────────────
# VALID_ARCHS is deliberately NOT set: deprecated since Xcode 12, ARCHS alone
# is authoritative and this keeps the invocation valid on modern Xcode.
echo "[2/4] xcodebuild..."
cd "$PROJECT_DIR"
xcodebuild \
  -project "$PROJECT_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -sdk "$SDK" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DD" \
  ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
  IPHONEOS_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)" | tail -20

[ -d "$APP" ] || { echo "ERROR: $APP not produced."; exit 1; }

# ── 3. Sign ─────────────────────────────────────────────────────────────────
# Frameworks/ only exists when the floor is below iOS 12.2 (Xcode then embeds
# the Swift runtime). Nested code must be signed before the enclosing bundle.
echo "[3/4] Signing (identity: $SIGN_IDENTITY)..."
if [ -d "$FWDIR" ]; then
  for f in "$FWDIR"/*.dylib; do
    [ -f "$f" ] && codesign --force --sign "$SIGN_IDENTITY" "$f"
  done
fi
codesign --force --sign "$SIGN_IDENTITY" "$APP"

# ── 4. Package IPA ──────────────────────────────────────────────────────────
echo "[4/4] Packaging IPA..."
rm -rf "$IPA_DIR" && mkdir -p "$IPA_DIR/Payload"
cp -r "$APP" "$IPA_DIR/Payload/"
cd "$IPA_DIR"
zip -qr "$PROJECT_NAME.ipa" Payload && rm -rf Payload
ls -lh "$IPA_DIR/$PROJECT_NAME.ipa"
BUILD
}

# ── Dispatch: remote over ssh, or local when BUILD_HOST is empty ─────────────
BASE_PATH="${REMOTE_BASE:-\$HOME/Documents/$PROJECT_NAME}"

if [ -n "$BUILD_HOST" ]; then
  echo "==> [min iOS $DEPLOYMENT_TARGET / $ARCHS] Building $PROJECT_NAME on $BUILD_HOST..."

  # Push the local sources up. No --delete: SERV2's copy is a mirror, but a
  # stray file there is harmless (the pbxproj decides what compiles) whereas an
  # accidental wipe of something the user put there by hand is not.
  if [ "$SYNC" = 1 ] && [ -d "$LOCAL_PROJECT_DIR" ]; then
    echo "[0/4] Syncing sources -> $BUILD_HOST..."
    sshpass -eSSHPASS ssh $SSH_OPTS "$BUILD_HOST" "mkdir -p \"$BASE_PATH/$PROJECT_NAME\""
    rsync -az --exclude 'DerivedData' --exclude 'build' \
               --exclude '.DS_Store' --exclude 'xcuserdata' \
      -e "sshpass -eSSHPASS ssh $SSH_OPTS" \
      "$LOCAL_PROJECT_DIR/" "$BUILD_HOST:$BASE_PATH/$PROJECT_NAME/"
  fi

  emit_build_script | sshpass -eSSHPASS ssh $SSH_OPTS "$BUILD_HOST" bash
  echo "==> Copying IPA to $OUTPUT_IPA..."
  sshpass -eSSHPASS scp $SSH_OPTS \
    "$BUILD_HOST:$BASE_PATH/build/$PROJECT_NAME.ipa" "$OUTPUT_IPA"
else
  echo "==> [min iOS $DEPLOYMENT_TARGET / $ARCHS] Building $PROJECT_NAME locally..."
  emit_build_script | bash
  LOCAL_BASE="${REMOTE_BASE:-$HOME/Documents/$PROJECT_NAME}"
  [ "$LOCAL_BASE/build/$PROJECT_NAME.ipa" = "$OUTPUT_IPA" ] || \
    cp "$LOCAL_BASE/build/$PROJECT_NAME.ipa" "$OUTPUT_IPA"
fi

echo "==> Done: $OUTPUT_IPA"
