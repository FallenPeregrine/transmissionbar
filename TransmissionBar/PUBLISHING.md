# Publish the 0.7 beta

The `TransmissionBar beta build` workflow builds on an Apple Silicon macOS runner, runs the Swift tests, bundles the engine, collects matching third-party sources/notices, checks signatures, verifies the DMG and uploads the release files. No release is published automatically.

## First upload

The source addition is prepared on branch `transmissionbar-0.7`. Review the diff before pushing, as required by this fork's root `CLAUDE.md`. The upstream source is preserved; the root README points to TransmissionBar and the upstream README is retained as `README.upstream.md`.

After the branch is pushed, open Actions. If GitHub displays a button to enable workflows for this fork, enable them. Review the `TransmissionBar beta build` result and download its `TransmissionBar-0.7-Apple-Silicon` artifact. A successful source push alone is not a successful macOS build.

Install the DMG on your Mac, confirm launch from Applications, add/remove a legal test torrent, test a plain hash, quit and relaunch, and check settings/session persistence. The workflow records the actual minimum macOS required by the bundled binaries in `build-info.json` and the generated release notes. Compatibility with that oldest OS requires separate installation testing.

## Create the release

Merge the reviewed branch into this fork's `main`. On Actions → TransmissionBar beta build → Run workflow, choose `main` and enable **Create a draft v0.7 prerelease**. This builds from that exact commit and creates the draft tag `transmissionbar-v0.7`. The distinct tag avoids confusing this app's release with Transmission's own upstream version tags.

Open Releases, review the draft notes and attached DMG, sources archive, checksums and build information, then publish it as a prerelease. Set the tested macOS version in the notes. If a draft with this tag already exists, review it in Releases rather than rerunning the create step; the workflow deliberately fails instead of overwriting a published release.

You can also build locally with `bash scripts/package-release.sh` from this folder and attach everything in `dist/release/` to a manually created prerelease. The sources archive and checksums belong beside the DMG. Do not upload build outputs into the Git repository itself.

Enable Issues in this fork's Settings if it is disabled. The TransmissionBar bug-report form is already in `.github/ISSUE_TEMPLATE/transmissionbar-bug.yml`.
