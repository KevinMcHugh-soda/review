#!/usr/bin/env bash
#
# make-signing-cert.sh — create a stable self-signed code-signing identity.
#
# Why: ad-hoc signing ("-") produces a cdhash-based designated requirement that
# changes on every build, so macOS treats each build as a different program.
# A stable self-signed cert keeps the designated requirement constant, which
# keeps any per-app permission you grant (local network, files) attached across
# rebuilds instead of resetting.
#
# Optional. Ad-hoc signing works fine; a stable identity only avoids
# re-granting permissions (e.g. folder access) after each build.
#
# Usage:  ./scripts/make-signing-cert.sh [identity-name]
#
# Expect ONE interactive authorization prompt from `security add-trusted-cert`.
set -euo pipefail

NAME="${1:-review-dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Note: `find-identity -v` filters to trust-evaluated identities and will NOT
# list this cert, because a self-signed cert is not a trusted anchor. That is
# fine — codesign does not require the cert to be trusted, only to exist with
# its private key. Query without -v.
if security find-identity -p codesigning | grep -q "\"$NAME\""; then
	echo "✓ identity '$NAME' already exists — nothing to do"
	exit 0
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

echo "→ generating self-signed code-signing cert '$NAME'"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
	-keyout "$T/key.pem" -out "$T/cert.pem" -subj "/CN=$NAME" \
	-addext "basicConstraints=critical,CA:false" \
	-addext "extendedKeyUsage=critical,codeSigning" \
	-addext "keyUsage=critical,digitalSignature" 2>/dev/null

# OpenSSL 3 defaults to PBES2/AES-256 with an SHA-256 MAC, which Apple's
# Security framework cannot read — `security import` fails with the misleading
# "MAC verification failed (wrong password?)". Force the legacy SHA1/3DES
# algorithms, and use a non-empty transport password, which macOS also prefers.
P12_PASS="review-import"
openssl pkcs12 -export -inkey "$T/key.pem" -in "$T/cert.pem" \
	-out "$T/$NAME.p12" -passout "pass:$P12_PASS" \
	-macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES 2>/dev/null

echo "→ importing into the login keychain (allowing codesign to use it)"
security import "$T/$NAME.p12" -k "$KEYCHAIN" -T /usr/bin/codesign -P "$P12_PASS"

# Deliberately NOT running `security add-trusted-cert`. It needs an
# interactive GUI authorization, and it is not required: codesign signs
# happily with an untrusted self-signed identity. Trust settings only matter
# for verifying someone else's signature, which is Gatekeeper's job on a
# distributed app — not ours on a locally built one.

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
	echo "✓ '$NAME' is ready — make run picks it up via SIGN_IDENTITY"
	echo
	echo "  The signature's designated requirement is now certificate-based"
	echo "  and stable across rebuilds, so granted permissions survive a rebuild."
	echo "  Verify any time with:  codesign -d -r- build/Review.app"
else
	echo "✗ '$NAME' was not imported." >&2
	echo "  Fall back to Keychain Access → Certificate Assistant →" >&2
	echo "  Create a Certificate, type 'Code Signing'. Or build ad-hoc" >&2
	echo "  (make build DEV_IDENTITY=-) and accept repeated Keychain prompts." >&2
	exit 1
fi
