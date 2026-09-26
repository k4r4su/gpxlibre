#!/usr/bin/env python3
"""Vérifie les traductions de GPXlibre (it31) — à lancer en fin d'itération.

1. Compile l'app avec SWIFT_EMIT_LOC_STRINGS=YES (clés extraites par le compilateur : littéraux
   SwiftUI, String(localized:)) dans un dossier temporaire.
2. Compare avec GPXlibre/Resources/<langue>.lproj/Localizable.strings (en, de, es, it).
3. Affiche les clés du code SANS traduction.
4. Signale tout `String(localized:)` du code sans `bundle: .appLanguage` : il ne suivrait pas la
   langue choisie dans Réglages (seuls les textes SwiftUI passent par la redirection du bundle).

Usage : python3 scripts/l10n_check.py   (code de sortie 1 s'il manque des traductions)
Les libellés connus seulement à l'exécution (L10n.dynamicKeys) sont couverts par les tests.
"""
import glob, json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ["en", "de", "es", "it"]

def strings_keys(path):
    keys = set()
    for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=', open(path, encoding="utf-8").read(), re.M):
        keys.add(m.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8"))
    return keys

def code_keys(derived):
    subprocess.run(["xcodebuild", "build", "-project", "GPXlibre.xcodeproj", "-scheme", "GPXlibre",
                    "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", derived,
                    "SWIFT_EMIT_LOC_STRINGS=YES", "-quiet"], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    keys = {}
    for f in glob.glob(os.path.join(derived, "Build/Intermediates.noindex/**/*.stringsdata"), recursive=True):
        data = json.load(open(f))
        for table, entries in data.get("tables", {}).items():
            for e in entries:
                keys.setdefault((table, e["key"]), data["source"].split("/GPXlibre/")[-1])
    return keys

def calls_without_bundle():
    found = []
    for f in glob.glob(os.path.join(ROOT, "GPXlibre/**/*.swift"), recursive=True):
        for number, line in enumerate(open(f, encoding="utf-8"), 1):
            if "String(localized:" in line and "bundle:" not in line and not line.strip().startswith("//"):
                found.append(f"{os.path.relpath(f, ROOT)}:{number}")
    return found

def main():
    with tempfile.TemporaryDirectory() as derived:
        keys = code_keys(derived)
    missing = 0
    for location in calls_without_bundle():
        print(f"String(localized:) sans bundle: .appLanguage — {location}")
        missing += 1
    for lang in LANGS:
        base = os.path.join(ROOT, "GPXlibre/Resources", f"{lang}.lproj")
        tables = {os.path.basename(p)[:-8]: strings_keys(p) for p in glob.glob(os.path.join(base, "*.strings"))}
        for (table, key), source in sorted(keys.items()):
            if key and key not in tables.get(table, set()):
                print(f"[{lang}] {table}: {key!r}  ({source})")
                missing += 1
    print(f"{len(keys)} clés dans le code, {missing} traductions manquantes")
    sys.exit(1 if missing else 0)

if __name__ == "__main__":
    main()
