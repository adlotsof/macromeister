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

## Data sources & licenses

- **Open Food Facts** (bundled `foods_off.db`) — ODbL 1.0: attribution and
  share-alike apply; the app carries the required attribution in-app
  (More → "Data sources & licenses") and in `NOTICE.md`.
- **USDA FoodData Central** (bundled `foods_common.db`) — public domain
  (CC0 1.0); attributed in-app and in `NOTICE.md`.

See `NOTICE.md` for the full terms.

## License

Private project. All application code, UI and branding are original.
