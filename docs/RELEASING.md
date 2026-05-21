# Releasing Codexeption

Codexeption publishes signed and notarized macOS builds from GitHub Actions when a `v*.*.*` tag is pushed.

## Release Output

The release workflow uploads these files to the repository's GitHub Releases page:

- `CodexNative-vX.Y.Z-macOS-signed-notarized.zip`
- `CodexNative-vX.Y.Z-macOS-signed-notarized.zip.sha256`

The `.zip` contains `CodexNative.app`, signed with a Developer ID Application certificate, notarized by Apple, and stapled.

## Required GitHub Secrets

Set these in GitHub:

`Repository Settings` -> `Secrets and variables` -> `Actions` -> `New repository secret`

Required secrets:

- `APPLE_TEAM_ID`
- `APPLE_CERTIFICATE_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`

Optional secret:

- `APPLE_SIGNING_IDENTITY`

If `APPLE_SIGNING_IDENTITY` is not set, the workflow uses `Developer ID Application`.

## Developer ID Certificate

Create a Developer ID Application certificate in the Apple Developer portal:

`Apple Developer` -> `Certificates, Identifiers & Profiles` -> `Certificates` -> `+` -> `Developer ID Application`

Export the installed certificate and private key from Keychain Access as a password-protected `.p12` file.

Convert it for GitHub Secrets:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Paste the result into `APPLE_CERTIFICATE_BASE64`. Put the `.p12` export password in `APPLE_CERTIFICATE_PASSWORD`.

## App Store Connect API Key

Create the notarization API key in App Store Connect:

`App Store Connect` -> `Users and Access` -> `Integrations` -> `App Store Connect API` -> `+`

Download the `.p8` key once. Keep these values:

- Key ID -> `APP_STORE_CONNECT_API_KEY_ID`
- Issuer ID -> `APP_STORE_CONNECT_API_ISSUER_ID`
- `.p8` file contents, base64 encoded -> `APP_STORE_CONNECT_API_KEY_BASE64`

Convert the `.p8` file:

```sh
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

## Publishing A Release

Create and push a semver tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The workflow creates or updates the GitHub Release for that tag:

`https://github.com/MarlonJD/codexeption/releases`

You can also run the workflow manually from the repository's `Actions` tab and pass an existing tag.

## Notes

- This is not a Mac App Store release. It is a Developer ID distribution release for direct download from GitHub.
- The workflow requires a paid Apple Developer Program membership because Developer ID certificates and notarization are Apple developer features.
- The app remains local-first and uses the user's existing Codex CLI authentication and `~/.codex` configuration.
