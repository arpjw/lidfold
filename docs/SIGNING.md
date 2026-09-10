# Release signing and notarization

LidFold releases are ad-hoc signed by default. The release workflow enables Developer ID signing
and Apple notarization only when all five repository secrets below are configured. If none are
present, the same workflow continues to produce ZIP and DMG artifacts without Developer ID trust.
A partial configuration fails the release instead of silently falling back to ad-hoc signing.

## Prerequisites

- An active Apple Developer Program membership.
- A `Developer ID Application` certificate and its private key, exported together as a
  password-protected PKCS #12 (`.p12`) file.
- An App Store Connect API key with permission to submit software for notarization. Keep the
  key's `.p8` file, key ID, and issuer ID.
- Repository administrator access for adding GitHub Actions secrets.

Never commit the certificate, private key, passwords, or App Store Connect key to the
repository.

## GitHub Actions secrets

Configure these names under **Repository settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded contents of the exported `.p12` file |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` file |
| `APPLE_NOTARY_KEY_BASE64` | Base64-encoded contents of the App Store Connect `.p8` API key |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API key ID, such as `ABC123DEFG` |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer UUID |

Generate the encoded values locally without printing them to the terminal:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_ABC123DEFG.p8 | pbcopy
```

Paste each clipboard value into the corresponding GitHub secret immediately, then clear the
clipboard. The workflow never writes these values to logs.

## What the workflow does

For a signed release, the workflow:

1. Decodes the certificate and API key into the GitHub runner's temporary directory.
2. Imports the Developer ID identity into a new temporary keychain.
3. Builds the universal app and signs it with a secure timestamp and hardened runtime.
4. Verifies the app signature before creating the ZIP and DMG.
5. Submits the DMG with `xcrun notarytool`, waits for Apple's result, staples the ticket, and
   validates it with both `stapler` and Gatekeeper's `spctl`.
6. Deletes the temporary keychain and credential files, including when an earlier step fails.

The workflow discovers the `Developer ID Application` identity from the imported certificate,
so the certificate's display name is not stored as another secret.

## Local signed packaging

If a Developer ID Application identity is already installed in your login keychain, pass its
exact name to the packaging script:

```sh
VERSION=1.2.3 \
SIGNING_IDENTITY="Developer ID Application: Example Developer (TEAMID1234)" \
scripts/package-release.sh
```

This signs and verifies the app but does not submit it to Apple. Notarization remains an
explicit release-CI operation so App Store Connect credentials do not need to live in the
development environment.
