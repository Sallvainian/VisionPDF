# VisionPDF

macOS GUI for OCRmyPDF (Swift/SwiftUI, Xcode project, no package manager).

## Releases & versioning

Releases are fully automated by release-please. The flow:

1. Push conventional commits to `main`.
2. release-please opens/updates a `chore(main): release X.Y.Z` PR
   (bumps `Version.xcconfig` + `version.txt`, writes `CHANGELOG.md`).
3. Merging that PR **is** the release: it creates tag `vX.Y.Z`, publishes the
   GitHub Release, and `.github/workflows/release.yml` builds, signs,
   notarizes, and attaches `VisionPDF-X.Y.Z.dmg` / `.zip`.

### Commit messages: conventional commits, always

release-please computes the next version from commit messages on `main`:

| Prefix                                | Effect        |
| ------------------------------------- | ------------- |
| `fix: …`                              | patch bump    |
| `feat: …`                             | minor bump    |
| `feat!: …` / `BREAKING CHANGE:` footer| major bump    |
| `chore:`, `docs:`, `ci:`, `refactor:`, `test:` | no release |

To force a specific version, add a `Release-As: X.Y.Z` footer (own paragraph)
to any commit.

### Never edit versions by hand

- `Version.xcconfig` is the **single source of truth** for the app version.
  Only the release PR bumps it (via the `x-release-please-*` annotations —
  keep those comment lines intact).
- Do NOT set `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in Xcode build
  settings / `project.pbxproj` — target-level values would silently shadow
  `Version.xcconfig` and ship wrongly-versioned builds. The project reads the
  xcconfig through a project-level base configuration reference.
- `CHANGELOG.md`, `version.txt`, and `.release-please-manifest.json` are also
  release-please-owned; don't edit them manually.

### Testing the build pipeline

Actions → Release → Run workflow: builds/signs/notarizes and uploads the
artifacts to the run only — it never touches a GitHub Release.
