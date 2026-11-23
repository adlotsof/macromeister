# Build the MacroTrack COMMON-FOODS database (the barcode-less whole-food
# basics) from USDA FoodData Central:
#   1. FNDDS 2021-2023 — familiar eating-occasion names ("Salad greens", raw
#      weights per portion) — preferred source.
#   2. SR Legacy 2019-04 — generic whole foods not in FNDDS — fallback.
# Both are per-100g nutrient tables; USDA data is public domain.
# Includes a kcal sanity guard: when the reported energy contradicts the
# Atwater estimate from macros (bogus 1008 values), fall back to Atwater.
import csv
import re
import sqlite3
import sys
import time

OUT = "foods_common.db"

ENERGY = {"1008"}
ENERGY_ATWATER = {"2047", "2048"}
PROTEIN = {"1003"}
FAT = {"1004"}
CARBS = {"1005"}
FIBER = {"1079"}
WANT = ENERGY | ENERGY_ATWATER | PROTEIN | FAT | CARBS | FIBER

FN_FOOD_ID = 1
FN_NUTRIENT_ID = 2
FN_AMOUNT = 3

# FNDDS uses short nutrient ids (energy=208); SR Legacy uses 1008+.
FN_ENERGY = {"208"}
FN_PROTEIN = {"203"}
FN_FAT = {"204"}
FN_CARBS = {"205"}
FN_FIBER = {"291"}


def _f(s):
    try:
        v = float(s)
        return v if v == v and 0 <= v < 10000 else None
    except (ValueError, TypeError):
        return None


def _norm(s):
    return re.sub(r'[^a-z ]', '', s.lower()).strip()


def _load_nutrients(path, mapping):
    """mapping: semantic key -> set of nutrient ids. Returns {fdc_id: {key: val}}."""
    nutr = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            if not row or row[0] == "id" or len(row) <= FN_AMOUNT:
                continue
            key = next((k for k, ids in mapping.items() if row[FN_NUTRIENT_ID] in ids), None)
            if key is None:
                continue
            v = _f(row[FN_AMOUNT])
            if v is None:
                continue
            nutr.setdefault(row[FN_FOOD_ID], {})[key] = v
    return nutr


SR_MAP = {"kcal": ENERGY | ENERGY_ATWATER, "protein": PROTEIN, "carbs": CARBS,
          "fat": FAT, "fiber": FIBER}
FN_MAP = {"kcal": FN_ENERGY, "protein": FN_PROTEIN, "carbs": FN_CARBS,
          "fat": FN_FAT, "fiber": FN_FIBER}


def _kcal_of(n):
    kcal = n.get("kcal")
    p, c, fa = n.get("protein", 0.0) or 0.0, n.get("carbs", 0.0) or 0.0, n.get("fat", 0.0) or 0.0
    atwater = p * 4 + c * 4 + fa * 9
    # Bogus-energy guard: if reported kcal contradicts Atwater-from-macros,
    # trust the macros (fixes e.g. dressings reported at 15 kcal/100g).
    if kcal is None or kcal <= 0 or (atwater > 10 and kcal < atwater * 0.45):
        kcal = atwater if atwater > 0 else kcal
    return kcal


def _row_of(fid, name, source, portion_g, n):
    kcal = _kcal_of(n)
    if kcal is None or kcal <= 0:
        return None
    return (
        f"{source}-{fid}",
        name.strip()[:120],
        "",
        source,
        portion_g,
        round(kcal, 1),
        round(n.get("protein", 0.0) or 0.0, 1),
        round(n.get("carbs", 0.0) or 0.0, 1),
        round(n.get("fat", 0.0) or 0.0, 1),
        round(n.get("fiber", 0.0) or 0.0, 1),
        None,  # micros: USDA rows don't track micronutrients (yet)
    )


def main():
    rows = {}
    seen_names = set()
    t0 = time.time()

    # ---- 1. FNDDS (familiar names + portion gram weights) ----
    fndds_foods = {}
    with open("fndds/food.csv", newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            if not row or row[0] == "fdc_id" or len(row) <= 2:
                continue
            fndds_foods[row[0]] = row[2]
    fndds_nutr = _load_nutrients("fndds/food_nutrient.csv", FN_MAP)
    portions = {}  # fdc_id -> best gram_weight (largest data_points then first)
    with open("fndds/food_portion.csv", newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            if not row or row[0] == "id" or len(row) <= 7:
                continue
            fid = row[1]
            gw = _f(row[7])
            if gw is None or gw <= 0 or gw > 5000:
                continue
            if fid not in portions:
                portions[fid] = gw
    n_added = 0
    for fid, name in fndds_foods.items():
        n = fndds_nutr.get(fid)
        if not n:
            continue
        key = _norm(name)
        if key in seen_names:
            continue
        r = _row_of(fid, name, "usda", portions.get(fid), n)
        if r is None:
            continue
        rows[r[0]] = r
        seen_names.add(key)
        n_added += 1

    # ---- 2. SR Legacy fallback (generic names not already present) ----
    sr_foods = {}
    with open("food.csv", newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            if not row or row[0] == "fdc_id" or len(row) <= 3:
                continue
            sr_foods[row[0]] = row[2]
    sr_nutr = _load_nutrients("food_nutrient.csv", SR_MAP)
    n_sr = 0
    for fid, name in sr_foods.items():
        n = sr_nutr.get(fid)
        if not n:
            continue
        key = _norm(name)
        if key in seen_names:
            continue
        r = _row_of(fid, name, "usda", None, n)
        if r is None:
            continue
        rows[r[0]] = r
        seen_names.add(key)
        n_sr += 1

    db = sqlite3.connect(OUT)
    db.execute("PRAGMA journal_mode=OFF")
    db.execute("PRAGMA synchronous=OFF")
    db.execute("DROP TABLE IF EXISTS foods")
    db.execute(
        "CREATE TABLE foods ("
        "code TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT, country TEXT,"
        "serving_g REAL, kcal REAL, protein REAL, carbs REAL,"
        "fat REAL, fiber REAL, micros TEXT)"
    )
    db.execute("CREATE INDEX idx_foods_name ON foods (name COLLATE NOCASE)")
    db.execute("CREATE INDEX idx_foods_brand ON foods (brand COLLATE NOCASE)")
    batch = list(rows.values())
    for i in range(0, len(batch), 5000):
        db.executemany(
            "INSERT OR REPLACE INTO foods VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            batch[i:i + 5000])
    db.commit()
    # FTS5 search index over name+brand: the app's food search uses this
    # instead of full-table LIKE scans (4.57M rows). contentless=False:
    # external-content table mapped by rowid, populated once here.
    db.execute("DROP TABLE IF EXISTS foods_fts")
    db.execute(
        # fts4 (not fts5): Android's system sqlite often lacks the fts5
        # module; fts4 with external content is available everywhere.
        "CREATE VIRTUAL TABLE foods_fts USING fts4(name, brand, "
        "content=foods)")
    db.execute(
        "INSERT INTO foods_fts(foods_fts) VALUES ('rebuild')")
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"DONE: fndds={n_added} sr_fallback={n_sr} total={len(rows)} "
          f"{time.time()-t0:.0f}s")


if __name__ == "__main__":
    sys.exit(main())
