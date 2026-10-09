#!/bin/sh
# Deploy gnosplit under your namespace, signed by your own gnokey key (this
# script never sees the key, gnokey asks for its password).
#
#   tools/deploy.sh [--dry-run] <gnokey key name> <namespace>
#
# e.g. tools/deploy.sh mykey nym-alexiscolin000 puts the packages at
# gno.land/p/nym-alexiscolin000/gnosplit/ledger/v0 and
# gno.land/r/nym-alexiscolin000/gnosplit/v1 on onyx. The realm imports gnotif,
# which exists on onyx only. Whoever deploys owns the realm (SetSuccessor).
#
# onyx parks a new package ("inert") until its approver enables it, in
# seconds, so the ledger goes first and the realm waits for it to be live.
set -eu
DRY=
[ "${1:-}" = --dry-run ] && { DRY=1; shift; }
[ $# -eq 2 ] || { sed -n '2,13p' "$0"; exit 2; }
KEY=$1 NS=$2
CHAIN=onyx-1 REMOTE=https://rpc.onyx.testnets.gno.land:443 WEB=https://onyx.testnets.gno.land
# onyx runs gno v1.5.0: gno and gnokey from that release, built once with Go
# into their own folder (your PATH is left alone).
command -v go >/dev/null || { echo "Go is needed to build gno and gnokey: https://go.dev/dl/" >&2; exit 1; }
TC=$HOME/.cache/gno-toolchains/onyx-v1.5.0
GNO=${GNO:-$TC/gno}
GNOKEY=${GNOKEY:-$TC/gnokey}
[ -x "$GNO" ] || { echo "building $GNO"; GOBIN=$TC go install github.com/gnolang/gno/gnovm/cmd/gno@v1.5.0; }
[ -x "$GNOKEY" ] || { echo "building $GNOKEY"; GOBIN=$TC go install github.com/gnolang/gno/gno.land/cmd/gnokey@v1.5.0; }
GNOROOT=${GNOROOT:-$(go env GOMODCACHE)/github.com/gnolang/gno@v1.5.0}
export GNOROOT
# Lint's own package cache, filled from onyx. gnokey keeps your usual
# GNOHOME, where your keys are.
LINTHOME=${LINTHOME:-$TC/gnohome}
cd "$(dirname "$0")/.."

LEDGER=gno.land/p/$NS/gnosplit/ledger/v0
REALM=gno.land/r/$NS/gnosplit/v1
OUT=build/$NS
rm -rf "$OUT" && mkdir -p "$OUT/ledger" "$OUT/realm"
touch "$OUT/gnowork.toml"
stage() { # src dir, out dir, pkgpath: the sources without tests, imports renamed
  for f in "$1"/*.gno; do
    case $f in *_test.gno) continue ;; esac
    sed "s#gno.land/p/gnosplit/ledger/v0#$LEDGER#" "$f" >"$2/$(basename "$f")"
  done
  printf 'module = "%s"\ngno = "0.9"\n' "$3" >"$2/gnomod.toml"
}
stage gno/p/gnosplit/ledger/v0 "$OUT/ledger" "$LEDGER"
stage gno/r/gnosplit/v1 "$OUT/realm" "$REALM"
echo "lint (gno v1.5.0, dependencies from onyx)"
(cd "$OUT" && GNOHOME=$LINTHOME "$GNO" mod download -remote-overrides "gno.land=$REMOTE" &&
  GNOHOME=$LINTHOME "$GNO" lint ./...) || { echo "lint failed: nothing submitted" >&2; exit 1; }

# live | inert | "" (absent), read from the node, no key needed
status() {
  curl -s -m 20 "$REMOTE/abci_query?path=%22vm/qpkgmeta_json%22&data=$(printf %s "$1" | base64 | tr -d '\n')" |
    python3 -c 'import sys,json,base64; print(json.loads(base64.b64decode(json.load(sys.stdin)["result"]["response"]["ResponseBase"]["Data"] or "e30=") or "{}").get("status", ""))' 2>/dev/null || true
}
deploy() { # dir, pkgpath
  dir=$1 path=$2
  if [ "$(status "$path")" = live ]; then echo "live already: $path"; return; fi
  set -- "$GNOKEY" maketx addpkg -pkgdir "$dir" -pkgpath "$path" -gas-fee 200000ugnot -gas-wanted 200000000 \
    -max-deposit 50000000ugnot -chainid "$CHAIN" -remote "$REMOTE" -broadcast "$KEY"
  if [ -n "$DRY" ]; then echo "would run: $*"; return; fi
  echo "submitting $path"; "$@"
  tries=0
  until [ "$(status "$path")" = live ]; do
    tries=$((tries + 1))
    [ $tries -le 36 ] || { echo "not live after 3 minutes: $path" >&2; exit 1; }
    sleep 5
  done
  echo "live: $path"
}
deploy "$OUT/ledger" "$LEDGER"
deploy "$OUT/realm" "$REALM"
[ -n "$DRY" ] && echo "dry run: nothing was signed" && exit 0
echo "done: $WEB/r/$NS/gnosplit/v1"
