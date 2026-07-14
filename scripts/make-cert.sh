#!/bin/sh
# One-time: create a self-signed codesigning identity ("CallScribe Dev") in a
# DEDICATED keychain whose password we control. A stable identity keeps the
# app's designated requirement constant across rebuilds, so TCC permission
# grants persist (ad-hoc signing pins the binary's cdhash and re-prompts every
# build).
#
# We use a dedicated keychain rather than the login keychain so that
# `set-key-partition-list` (which lets codesign use the private key without a
# GUI prompt) can run non-interactively — it needs the keychain password, and
# here we own it.
set -eu

IDENTITY="CallScribe Dev"
KEYCHAIN_NAME="callscribe-signing.keychain-db"
KEYCHAIN="$HOME/Library/Keychains/$KEYCHAIN_NAME"
KEYCHAIN_PASS="callscribe"

# Note: we list with `-p codesigning` (not `-v`): the cert is self-signed and
# thus "not trusted", so it never shows under `-v` (valid only) — but codesign
# signs with it fine. Trust is only needed for Gatekeeper verification, which a
# local unnotarized build doesn't use.
if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    echo "Codesigning identity '$IDENTITY' already exists in $KEYCHAIN_NAME:"
    security find-identity -p codesigning "$KEYCHAIN" | grep "$IDENTITY"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

openssl req -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" \
    -x509 -days 3650 -out "$TMP/cert.pem" \
    -subj "/CN=$IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:FALSE"

# OpenSSL 3.x defaults (AES/PBKDF2/SHA-256 MAC) break `security import`;
# force the SHA1-3DES PBE suite that the macOS keychain understands.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:callscribe -name "$IDENTITY" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

# Fresh dedicated keychain (delete any stale one first).
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # no auto-lock timeout

# Add it to the search list so codesign can find the identity by name.
EXISTING=$(security list-keychains -d user | sed -e 's/[" ]//g')
security list-keychains -d user -s "$KEYCHAIN" $EXISTING

security import "$TMP/cert.p12" -k "$KEYCHAIN" -P callscribe \
    -T /usr/bin/codesign -T /usr/bin/security

# Let codesign use the private key without a GUI prompt. We own this keychain's
# password, so this runs non-interactively (unlike the login keychain).
security set-key-partition-list -S apple-tool:,apple: -s \
    -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null

# Deliberately NOT trusting the cert (`add-trusted-cert -r trustRoot`): it pops
# a GUI authorization dialog and buys nothing here — codesign signs with an
# untrusted self-signed identity, and the resulting designated requirement pins
# the certificate (stable across rebuilds → TCC grants persist).

echo
echo "Created identity in $KEYCHAIN_NAME:"
security find-identity -p codesigning "$KEYCHAIN" | grep "$IDENTITY"
