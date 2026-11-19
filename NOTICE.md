# Data sources and licenses

MacroTrack bundles two food-composition databases, built from public datasets
by `tools/fetch_food_data.sh` at build time:

## Open Food Facts — ODbL 1.0 (attribution + share-alike required)

Source: https://world.openfoodfacts.org/data
(c) Open Food Facts contributors.

The Open Food Facts database is made available under the Open Database
License (ODbL) 1.0, https://opendatacommons.org/licenses/odbl/1-0; the
individual database contents under the Database Contents License.

The bundled `assets/foods_off.db` is a **derivative database** of the Open
Food Facts database (filtered to products with a name; nutrient fields
normalized per 100 g; per-product rows preserved with their original IDs and
last-modified timestamps). As the ODbL requires:

- **Attribution** — the app shows this notice in More → "Data sources &
  licenses" (`lib/ui/more/data_sources_screen.dart`):
  "This app contains information from Open Food Facts
  (https://world.openfoodfacts.org), which is made available here under the
  Open Database License (ODbL) 1.0."
- **Share-alike** — any redistribution of `foods_off.db` (or a further
  derivative database) must be licensed under the ODbL 1.0 and keep this
  attribution. The application code itself is a separate work and is not
  covered by the ODbL.
- **Modifications** — indicated here: filtering to named products,
  unit normalization, SQLite conversion, incremental delta updates.
- **Images** — product photos are not redistributed by this app (no image
  URLs are fetched or stored).

## USDA FoodData Central — public domain (CC0 1.0)

Source: https://fdc.nal.usda.gov/download-datasets

`assets/foods_common.db` is built from USDA FoodData Central:
- FNDDS 2021-2023 (familiar eating-occasion food names and portions)
- SR Legacy, April 2018 (generic whole foods, fallback)

USDA FoodData Central data are in the public domain, published under
CC0 1.0 Universal. No permission needed; the USDA requests attribution:
U.S. Department of Agriculture, Agricultural Research Service. FoodData
Central. fdc.nal.usda.gov.

## Application code

All application code, UI and branding are original, private work, and are
not licensed under the data licenses above.
