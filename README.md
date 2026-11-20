# MacroTrack

A local-first nutrition and macro tracker for Android (Flutter). All data
stays on your device — no account, no cloud, no tracking.

## Features

- **Food logging** — search 4.5M+ packaged products from a bundled Open Food
  Facts database (offline), USDA common foods, your own custom foods, and
  recipes. Barcode scanning and AI-assisted describe-a-meal/label-photo
  logging (bring your own OpenRouter/OpenAI key).
- **Adaptive coaching** — weekly check-ins with a documented energy-balance
  expenditure model that converges on your real intake/weight data, then
  recomputes daily calorie and macro targets automatically.
- **Weight & body-fat tracking** — daily weigh-ins with trend calculation.
- **Habits** — simple daily habit tracking with streaks.
- **Full data ownership** — per-area CSV exports, one-file JSON backup and
  restore, and an importer for MacroFactor Excel exports (weights, body-fat,
  daily totals, custom foods, recipes, program settings and expenditure
  history).
- **Food database updates** — incremental Open Food Facts delta updates,
  checked weekly (or manually from More).

## Requirements

- Flutter (see `pubspec.yaml` for the SDK constraint)
- Android min SDK 26

The two bundled SQLite food databases (`assets/foods_off.db`,
`assets/foods_common.db`) are **not** in this repository (too large for git).
`./tools/fetch_food_data.sh` downloads the public datasets (Open Food Facts
dump, USDA FNDDS + SR Legacy) and builds both into `assets/`. GitHub Actions
does this automatically on every push (see `.github/workflows/build.yml`),
which also publishes the release APK as a build artifact.

## Build

```sh
flutter pub get
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

## Releases

- **Tag → GitHub Release + Play internal track.** Pushing a tag `v*` runs
  `.github/workflows/release.yml`: it builds a signed AAB + APK, attaches the
  APK to a GitHub Release and uploads the AAB to the Google Play **internal**
  track.
- **Semi-annual maintenance release.** `.github/workflows/maintenance-release.yml`
  runs on Jan 1 and Jul 1 (Google Play deactivates accounts without an app
  update for ~6 months): it bumps the build number, commits + tags, which
  triggers the release workflow, and uploads the bundle to the internal track.
  Run it on demand via *workflow_dispatch*.
- **Signing.** Release signing uses `android/key.properties` + a keystore,
  both gitignored. Locally, drop them into place; on CI they are injected
  from secrets (see below). Without them the build falls back to the debug
  key.

### Required GitHub secrets (Settings → Secrets and variables → Actions)

| Secret | Meaning |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | base64 of the release keystore (`base64 -i macrotrack-release.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | keystore store password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |
| `PLAY_SERVICE_ACCOUNT_JSON` | Play Console service-account JSON (Play API access enabled for the internal track) |

Secrets are never committed; the workflows read them at run time. If the
Play service-account secret is missing, the Play upload step is skipped and
only the GitHub Release is created.

## Data sources & licenses

- **Open Food Facts** (bundled `foods_off.db`) — ODbL 1.0: attribution and
  share-alike apply; the app carries the required attribution in-app
  (More → "Data sources & licenses") and in `NOTICE.md`.
- **USDA FoodData Central** (bundled `foods_common.db`) — public domain
  (CC0 1.0); attributed in-app and in `NOTICE.md`.

See `NOTICE.md` for the full terms.

## License

Private project. All application code, UI and branding are original.
