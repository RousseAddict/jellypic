#!/bin/bash
# deploy.sh — provision the App Review demo server.
#
# Ships this folder to the VPS and runs site.yml there, against localhost, with
# Debian's own ansible-core (builtin modules only: no Galaxy collection, no pip).
# Nothing runs on this Mac but ssh and tar, so there is no Ansible to install
# here, and the controller is the same Debian the playbook targets.
#
# This folder is the source of truth. The copy on the VPS is deleted and
# replaced on every run: never edit it there.
#
# Credentials are never stored in a tracked file:
#   .env.local          DEMO_PASS (ssh password) and optionally DEMO_HOST.
#                       Leave DEMO_PASS unset once the VPS takes your ssh key.
#   secrets.local.yml   Jellyfin passwords, see secrets.example.yml.
# Both are gitignored. secrets.local.yml travels to the VPS inside the tarball,
# into a 0700 directory, because the playbook needs it there.
#
# Usage:
#   ./deploy.sh                       # full run
#   ./deploy.sh --tags configure      # any argument goes to ansible-playbook
#   ./deploy.sh --check --diff        # dry run

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

ENV_LOCAL="$HERE/.env.local"
# shellcheck source=/dev/null
[ -f "$ENV_LOCAL" ] && . "$ENV_LOCAL"

DEMO_HOST="${DEMO_HOST:-debian@167.114.120.111}"
REMOTE_DIR="${REMOTE_DIR:-demo-server}"

if [ ! -f "$HERE/secrets.local.yml" ]; then
  echo "ERROR: $HERE/secrets.local.yml is missing (template: secrets.example.yml)." >&2
  exit 1
fi

# Keepalives: the first seed build is minutes of silence (downloads, two video
# encodes), and on 2026-11-24 an idle session was dropped mid-build ("Broken
# pipe"), taking the playbook down with it before the library was filled.
SSH=(ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new
     -o ServerAliveInterval=30 -o ServerAliveCountMax=4)
if [ -n "${DEMO_PASS:-}" ]; then
  # A 0600 temp file and sshpass -f, not -e: on 2026-11-23, two of six -e
  # connections in a row reached sshd with an empty password (rejected before
  # PAM ran, per the server's journal), while -f never failed. -p is out
  # either way: it puts the password in the process arguments, readable
  # through ps. printf is a builtin, so it never appears there.
  PASS_FILE="$(mktemp)"
  trap 'rm -f "$PASS_FILE"' EXIT
  printf '%s\n' "$DEMO_PASS" > "$PASS_FILE"
  SSH=(sshpass -f "$PASS_FILE" "${SSH[@]}" -o PubkeyAuthentication=no)
fi
SSH+=("$DEMO_HOST")

# --no-install-recommends matters: ansible-core recommends Debian's "ansible"
# package, thousands of community collections this playbook never uses, and
# byte-compiling them takes the better part of ten minutes on this VPS.
echo "==> ansible-core on $DEMO_HOST"
"${SSH[@]}" 'command -v ansible-playbook >/dev/null || {
  sudo apt-get update -q && sudo DEBIAN_FRONTEND=noninteractive \
    apt-get install -y -q --no-install-recommends ansible-core; }'

echo "==> shipping $(basename "$HERE")/"
COPYFILE_DISABLE=1 tar -czf - -C "$HERE" --exclude .env.local --exclude .DS_Store . \
  | "${SSH[@]}" "rm -rf ~/$REMOTE_DIR && mkdir -m 700 ~/$REMOTE_DIR && tar -xzf - -C ~/$REMOTE_DIR"

echo "==> ansible-playbook site.yml $*"
ARGS=""
[ $# -gt 0 ] && ARGS="$(printf ' %q' "$@")"
"${SSH[@]}" "cd ~/$REMOTE_DIR && sudo ANSIBLE_FORCE_COLOR=1 ansible-playbook -i localhost, -c local site.yml$ARGS"
