"""Erzeugt die kompakte BLS-Tabelle der App aus der Excel-Datei des Max Rubner-Instituts.

Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0. Karlsruhe.
Kostenfrei nutzbar, Quelle angeben (Dokumentation, Abschnitt 9.3).
Aufruf: python3 -I tools/bls/convert.py BLS_4_0_Daten_2025_DE.xlsx ios/Packages/CoachCore/Sources/CoachCore/Resources/bls.tsv
Benötigt openpyxl. Werte je 100 g, Spalten wie `Nutrient` in CoachCore (Omega-3 = EPA + DHA in mg).
"""

import sys

import openpyxl

# Spalte der App -> BLS-Nährstoffcode(s) und Faktor.
COLUMNS = [
    ("kcal", ["ENERCC"], 1),
    ("protein_g", ["PROT625"], 1),
    ("carbs_g", ["CHO"], 1),
    ("sugar_g", ["SUGAR"], 1),
    ("fat_g", ["FAT"], 1),
    ("satfat_g", ["FASAT"], 1),
    ("fiber_g", ["FIBT"], 1),
    ("water_ml", ["WATER"], 1),
    ("sodium_mg", ["NA"], 1),
    ("potassium_mg", ["K"], 1),
    ("magnesium_mg", ["MG"], 1),
    ("calcium_mg", ["CA"], 1),
    ("iron_mg", ["FE"], 1),
    ("zinc_mg", ["ZN"], 1),
    ("vitd_ug", ["VITD"], 1),
    ("b12_ug", ["VITB12"], 1),
    ("vitc_mg", ["VITC"], 1),
    ("iodine_ug", ["ID"], 1),
    ("omega3_mg", ["F20:5CN3", "F22:6CN3"], 1000),
]


def number(value):
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def fmt(value):
    if value is None:
        return ""
    text = f"{value:.4g}"
    return "0" if text in ("-0", "0") else text


def main(source, target):
    sheet = openpyxl.load_workbook(source, read_only=True).worksheets[0]
    rows = sheet.iter_rows(values_only=True)
    header = next(rows)
    index = {}
    for position, title in enumerate(header):
        if isinstance(title, str) and title.endswith("]") and " " in title:
            index.setdefault(title.split(" ", 1)[0], position)
    missing = [code for _, codes, _ in COLUMNS for code in codes if code not in index]
    if missing:
        raise SystemExit(f"Spalten fehlen: {missing}")
    lines = ["# Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0. Karlsruhe. Auszug, je 100 g", "code\tname\t" + "\t".join(c for c, _, _ in COLUMNS)]
    for row in rows:
        code, name = row[0], row[1]
        if not code or not name:
            continue
        values = []
        for _, codes, factor in COLUMNS:
            parts = [number(row[index[c]]) for c in codes]
            values.append(None if any(p is None for p in parts) else sum(parts) * factor)
        if values[0] is None:
            continue
        clean = " ".join(str(name).replace("\t", " ").split())
        lines.append("\t".join([str(code), clean] + [fmt(v) for v in values]))
    with open(target, "w", encoding="utf-8") as out:
        out.write("\n".join(lines) + "\n")
    print(f"{len(lines) - 2} Lebensmittel -> {target}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
