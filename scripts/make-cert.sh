#!/bin/sh
# One-time: create a self-signed codesigning identity ("CallScribe Dev") in the
# login keychain. A stable identity keeps the app's designated requirement
# constant across rebuilds, so TCC permission grants persist (ad-hoc signing
# ties grants to the binary hash and re-prompts on every build).
set -eu

IDENTITY="CallScribe Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "Codesigning identity '$IDENTITY' already exists and is valid:"
    security find-identity -v -p codesigning | grep "$IDENTITY"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    # Cert + key already imported; only the trust step is missing.
    echo "Certificate already in keychain; re-applying trust settings."
    security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$TMP/cert.pem"
else
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

    security import "$TMP/cert.p12" -k "$KEYCHAIN" -P callscribe -T /usr/bin/codesign
fi

# Mark the cert trusted for code signing — this pops ONE macOS authorization
# dialog; approve it with your login password.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo
echo "Created identity:"
security find-identity -v -p codesigning
