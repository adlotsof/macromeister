# Build the MacroTrack offline food database from the full Open Food Facts
# product dump (en.openfoodfacts.org.products.csv.gz).
# Keeps EVERY product that has a name (macros optional — NULL when the dump
# lacks them), written to a compact SQLite file bundled as a Flutter asset:
# assets/foods_off.db
import csv
import gzip
import json
import sqlite3
import sys
import time

SRC = "off_products.csv.gz"
OUT = "foods_off.db"

# OFF dump is tab-separated, with quoted fields containing tabs/newlines.
IDX = {
    "code": 0,
    "product_name": 10,
    "brands": 18,
    "countries_tags": 40,
    "serving_quantity": 51,
    "kcal": 89,       # energy-kcal_100g
    "kj": 90,         # energy_100g (kJ) fallback
    "fat": 92,
    "carbs": 129,
    "fiber": 146,
    "protein": 150,
}


def _f(s):
    try:
        v = float(s)
        return v if v == v and 0 <= v < 10000 else None
    except (ValueError, TypeError):
        return None


def main():
    db = sqlite3.connect(OUT)
    db.execute("PRAGMA journal_mode=OFF")
    db.execute("PRAGMA synchronous=OFF")
    db.execute("PRAGMA temp_store=MEMORY")
    db.execute("DROP TABLE IF EXISTS foods")
    db.execute(
        "CREATE TABLE foods ("
        "code TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT, country TEXT,"
        "serving_g REAL, kcal REAL, protein REAL, carbs REAL,"
        "fat REAL, fiber REAL)"
    )
    db.execute(
        "CREATE INDEX idx_foods_name ON foods (name COLLATE NOCASE)"
    )
    db.execute("CREATE INDEX idx_foods_brand ON foods (brand COLLATE NOCASE)")

    total = kept = 0
    t0 = time.time()
    batch = []
    with gzip.open(SRC, "rt", encoding="utf-8", errors="replace") as f:
        # The dump contains stray NUL bytes; strip them per line before parsing.
        reader = csv.reader((line.replace("\0", "") for line in f),
                            delimiter="\t", quoting=csv.QUOTE_MINIMAL)
        header = next(reader)  # skip header row
        for row in reader:
            total += 1
            if len(row) <= IDX["protein"]:
                continue
            name = (row[IDX["product_name"]] or "").strip()
            if not name or len(name) > 120:
                continue
            kcal = _f(row[IDX["kcal"]])
            if kcal is None:
                kj = _f(row[IDX["kj"]])
                if kj is not None:
                    kcal = kj / 4.184
            if kcal is not None and kcal <= 0:
                kcal = None
            protein = _f(row[IDX["protein"]])
            carbs = _f(row[IDX["carbs"]])
            fat = _f(row[IDX["fat"]])
            brand = (row[IDX["brands"]] or "").split(",")[0].strip()[:80]
            ct = (row[IDX["countries_tags"]] or "").split(",")
            country = ct[0].removeprefix("en:").strip()[:24] if ct and ct[0] else ""
            serving = _f(row[IDX["serving_quantity"]])
            batch.append((
                (row[IDX["code"]] or "")[:40], name, brand, country,
                serving,
                round(kcal, 1) if kcal is not None else None,
                round(protein, 1) if protein is not None else None,
                round(carbs, 1) if carbs is not None else None,
                round(fat, 1) if fat is not None else None,
                _f(row[IDX["fiber"]]) or 0.0,
            ))
            if len(batch) >= 50000:
                db.executemany(
                    "INSERT OR REPLACE INTO foods VALUES (?,?,?,?,?,?,?,?,?,?)",
                    batch)
                kept += len(batch)
                batch = []
                print(f"  {kept} rows, {time.time()-t0:.0f}s", flush=True)
    if batch:
        db.executemany(
            "INSERT OR REPLACE INTO foods VALUES (?,?,?,?,?,?,?,?,?,?)", batch)
        kept += len(batch)
    db.commit()
    db.execute("VACUUM")
    db.execute("PRAGMA optimize")
    db.close()
    print(f"DONE: {total} products scanned, {kept} foods kept, "
          f"{time.time()-t0:.0f}s")


if __name__ == "__main__":
    sys.exit(main())
