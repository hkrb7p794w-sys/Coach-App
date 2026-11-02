#!/usr/bin/env python3
"""Übungsbibliothek und BLS-Tabelle für die Android-App aus CoachCore (Swift) übernehmen.

Liest `ExerciseLibrary.swift` (Übungen mit Anleitung) und `ExerciseCatalog.swift` (Gewichtssprünge aus dem
Garmin-Katalog) und schreibt `android/app/src/main/assets/exercises.json`. So haben iPhone und Android dieselben
Übungen, IDs und Progressionsregeln. Dazu wird `Resources/bls.tsv` (Bundeslebensmittelschlüssel) unverändert nach
`assets/bls.tsv` kopiert. `--check` meldet nur, ob beide Dateien aktuell sind (für CI).
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
GYM = ROOT / "ios/Packages/CoachCore/Sources/CoachCore/Gym"
OUT = ROOT / "android/app/src/main/assets/exercises.json"
BLS_IN = ROOT / "ios/Packages/CoachCore/Sources/CoachCore/Resources/bls.tsv"
BLS_OUT = ROOT / "android/app/src/main/assets/bls.tsv"

GROUPS = {
    "chest": "Brust", "back": "Rücken", "shoulders": "Schultern", "biceps": "Bizeps", "triceps": "Trizeps",
    "legs": "Beine", "core": "Rumpf", "forearms": "Unterarme", "other": "Sonstige",
}


def catalog_rules(text: str) -> dict:
    pattern = re.compile(
        r'rule\(\s*"([^"]+)",\s*"[^"]+",\s*\.\w+,\s*#"[^"]*"#,\s*\d+\.\.\.\d+,\s*compound:\s*\w+,'
        r'\s*step:\s*([\d.]+),\s*percent:\s*([\d.]+)', re.S)
    rules = {}
    for match in pattern.finditer(text):
        rules.setdefault(match.group(1), (float(match.group(2)), float(match.group(3))))
    return rules


def split_args(text: str) -> list:
    """Teilt die Argumente eines `item(…)`-Aufrufs an Kommas der obersten Ebene."""
    parts, depth, current, in_string = [], 0, "", False
    for index, char in enumerate(text):
        if char == '"' and text[index - 1] != "\\":
            in_string = not in_string
        if not in_string:
            if char in "([":
                depth += 1
            elif char in ")]":
                depth -= 1
            elif char == "," and depth == 0:
                parts.append(current.strip())
                current = ""
                continue
        current += char
    if current.strip():
        parts.append(current.strip())
    return parts


def parse_list(text: str) -> list:
    inner = text.strip()[1:-1].strip()
    return [] if not inner else [item.strip() for item in split_args(inner)]


def library(text: str, rules: dict) -> list:
    body = text.split("public static let all: [ExerciseInfo] = [", 1)[1].split("\n  ]\n", 1)[0]
    exercises = []
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("item("):
            continue
        args = split_args(line[len("item("):line.rindex(")")])
        positional = [arg for arg in args if not re.match(r"^\w+:", arg)]
        named = dict(arg.split(":", 1) for arg in args if re.match(r"^\w+:", arg))
        named = {key.strip(): value.strip() for key, value in named.items()}
        exercise_id = json.loads(positional[0])
        catalog = rules.get(exercise_id)
        step = float(named["step"]) if "step" in named else (catalog[0] if catalog else 2.5)
        percent = float(named["percent"]) if "percent" in named else (catalog[1] if catalog else 2.5)
        exercises.append({
            "id": exercise_id,
            "name": json.loads(positional[1]),
            "group": GROUPS[positional[2].lstrip(".")],
            "secondary": [GROUPS[item.lstrip(".")] for item in parse_list(positional[3])],
            "equipment": [item.lstrip(".") for item in parse_list(positional[4])],
            "tracking": named.get("tracking", ".weightReps").lstrip("."),
            "compound": named["compound"] == "true",
            "lowerReps": int(positional[5]),
            "upperReps": int(positional[6]),
            "step": step,
            "percent": percent,
            "instructions": [json.loads(item) for item in parse_list(positional[7])],
        })
    return exercises


def main() -> int:
    rules = catalog_rules((GYM / "ExerciseCatalog.swift").read_text(encoding="utf-8"))
    exercises = library((GYM / "ExerciseLibrary.swift").read_text(encoding="utf-8"), rules)
    if len(exercises) < 40:
        print(f"Nur {len(exercises)} Übungen gefunden – hat sich das Swift-Format geändert?", file=sys.stderr)
        return 1
    content = json.dumps(exercises, ensure_ascii=False, indent=1) + "\n"
    bls = BLS_IN.read_bytes()
    if "--check" in sys.argv:
        stale = []
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != content:
            stale.append("exercises.json")
        if not BLS_OUT.exists() or BLS_OUT.read_bytes() != bls:
            stale.append("bls.tsv")
        if stale:
            print(f"{', '.join(stale)} veraltet: python3 android/tools/export_exercises.py", file=sys.stderr)
            return 1
        print(f"exercises.json ({len(exercises)} Übungen) und bls.tsv aktuell")
        return 0
    OUT.write_text(content, encoding="utf-8")
    BLS_OUT.write_bytes(bls)
    print(f"{len(exercises)} Übungen und BLS-Tabelle nach {OUT.parent.relative_to(ROOT)} geschrieben")
    return 0


if __name__ == "__main__":
    sys.exit(main())
