# Release checklist

Use this checklist for a public source release or macOS binary release.

## Public source repository

1. Start from a clean export of the working tree. Do not publish an older development `.git` directory unless its complete history has been independently secret-scanned and rewritten where required.
2. Confirm `dist/`, `boujoy-config.json`, `runtime/`, `vault/`, `.env*`, session data, and generated logs are ignored and absent from `git ls-files`.
3. Confirm the required repository files are present: `README.md`, `LICENSE`, `SECURITY.md`, `THIRD_PARTY_NOTICES.md`, and `assets/LICENSE-OFL`.
4. Run the isolated test suite:

   ```bash
   env PYTHONDONTWRITEBYTECODE=1 python3 tests/smoke_test.py --skip-live
   ```

5. Run `git diff --check`, `node --check web/app.js`, and a secret scanner before tagging.

## Binary release

1. Build from a clean portable package root with relative `boujoy-config.json` paths.
2. Confirm the root contains the generated `启动 Boujoy Harness.command`; after extraction, launch through it once and verify it supplies the package root correctly.
3. Verify the app with `codesign --verify --deep --strict --verbose=2 "Boujoy Harness.app"`.
4. Sign with a Developer ID certificate and notarize before telling users that Gatekeeper will accept the download. An ad-hoc signature is suitable only for local testing.
5. Retain DeepSeek Harness and all bundled dependency notices when redistributing its runtime.
6. Create the archive without Finder metadata such as `__MACOSX/`, validate it with `unzip -tq`, publish a SHA-256 checksum, and test it after extraction on a clean macOS account. Also test a direct `.app` launch: the recovery picker must be clear and must not reveal temporary App Translocation paths.

## Windows binary release (beta)

1. Build/install the DeepSeek Harness runtime on a real Windows 10/11 x64 machine. Do not reuse the macOS `runtime/`; the package has native dependencies.
2. Assemble with `windows/Build-Windows-Portable.ps1`, passing only a reviewed public/demo vault and a Windows-native runtime.
3. Run `启动 Boujoy Harness.cmd` from the extracted package. Verify gateway health, knowledge/clean mode switches, file upload, dialog cancellation, a normal Agent turn, and the in-product restart command.
4. Run `关闭 Boujoy Harness.cmd` and confirm it stops only the recorded package processes; do not use process-name-wide kill commands in the release flow.
5. Record the tested Windows build number, Node/Python versions, DeepSeek Harness version, archive SHA-256, and clean-machine result before calling the archive share-ready.

## Final privacy check

Search both the repository and the release archive for credentials, private paths, user names, access codes, saved chats, and vault Markdown. Treat any positive finding as a release blocker until it has been reviewed.
