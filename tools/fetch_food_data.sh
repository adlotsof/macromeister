#!/usr/bin/env bash
# Downloads the raw food datasets and builds the two bundled SQLite assets:
#   assets/foods_off.db     — Open Food Facts (all products with a name)
#   assets/foods_common.db  — USDA FNDDS + SR Legacy whole foods
# Run from anywhere; outputs are copied into ../assets relative to this dir.
set -euo pipefail
cd "$(dirname "$0")"
# The assets/ dir contains no tracked files (the DBs are built here and
# gitignored), so it doesn't exist in a fresh CI checkout.
mkdir -p ../assets

BASE="https://raw.githubusercontent.com/ByteBeamLLC/extractor/main/data/nutrition-datasets"

fetch() { # fetch <url> <dest>
  if [ -s "$2" ]; then echo "cached: $2"; return; fi
  echo "downloading $2"
  curl -fL --retry 3 -o "$2" "$1"
}

# ---- Open Food Facts full dump (~1.5 GB compressed) ----
fetch "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz" \
  "off_products.csv.gz"
python3 build_off_db.py
cp foods_off.db ../assets/foods_off.db

# ---- USDA FNDDS (familiar eating-occasion names + portions) ----
mkdir -p fndds
for f in food.csv food_nutrient.csv food_portion.csv; do
  fetch "$BASE/usda_fndds/$f" "fndds/$f"
done

# ---- USDA SR Legacy (generic whole foods, fallback) ----
fetch "$BASE/usda_sr_legacy/food.csv" "food.csv"
fetch "$BASE/usda_sr_legacy/food_nutrient.csv" "food_nutrient.csv"

python3 build_common_db.py
cp foods_common.db ../assets/foods_common.db

echo "done:"
ls -la ../assets/foods_off.db ../assets/foods_common.db
