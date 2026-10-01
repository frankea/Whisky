#!/usr/bin/env python3
#
# fill-missing-translations.py
#
# This file is part of Whisky.
#
# Whisky is free software: you can redistribute it and/or modify it under the terms
# of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with Whisky.
# If not, see https://www.gnu.org/licenses/.
#
# Fills the compiled string tables of every localization in a built bundle with
# the English value of any key that localization lacks.
#
# Localizable.xcstrings uses identifiers (`library.title`) as keys, and Crowdin
# exports only the strings that were actually translated. macOS picks one
# localization per process and does not fall back to en key by key, so every
# untranslated string would otherwise render as its raw identifier. Filling the
# gap at build time keeps the committed catalog exactly as Crowdin manages it.
#
# Runs as a build phase of the Whisky target, after Copy Bundle Resources:
#
#   ./scripts/fill-missing-translations.py <Resources dir>          fill in place
#   ./scripts/fill-missing-translations.py --check <Resources dir>  exit 1 if a
#                                                                   key is missing
#
# Python 3.9 compatible: Xcode's bundled python3 runs it during builds.

import pathlib
import plistlib
import sys

SOURCE_LANGUAGE = "en"
TABLE_SUFFIXES = (".strings", ".stringsdict")


def load_plist(path: pathlib.Path) -> dict:
    """Reads a compiled .strings or .stringsdict in any of the formats Xcode
    writes: binary, UTF-8 XML, or UTF-16 XML (the Debug default, which plistlib
    cannot parse directly because of its encoding declaration)."""
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        text = data.decode("utf-16")
        text = text.replace('encoding="UTF-16"', 'encoding="UTF-8"', 1)
        data = text.encode("utf-8")
    return plistlib.loads(data)


def tables(lproj: pathlib.Path) -> dict:
    """Maps table name (Localizable) to {suffix: path} for one .lproj."""
    found: dict = {}
    for path in lproj.iterdir():
        if path.suffix in TABLE_SUFFIXES:
            found.setdefault(path.stem, {})[path.suffix] = path
    return found


def missing_keys(source: dict, target: dict) -> dict:
    """For each table file the source language has, returns the keys whose
    entries the target lacks from both its .strings and .stringsdict, keyed by
    suffix. A key the target has in either file counts as translated, so a
    plural translation is never shadowed by a plain English entry or vice versa."""
    result: dict = {}
    for name, files in source.items():
        present: set = set()
        for path in target.get(name, {}).values():
            present.update(load_plist(path))
        for suffix, path in files.items():
            entries = load_plist(path)
            gaps = {key: entries[key] for key in entries if key not in present}
            if gaps:
                result[(name, suffix)] = gaps
    return result


def localizations(resources: pathlib.Path) -> list:
    return sorted(
        p for p in resources.glob("*.lproj")
        if p.is_dir() and p.stem not in (SOURCE_LANGUAGE, "Base")
    )


def main(argv: list) -> int:
    check = "--check" in argv
    args = [a for a in argv if a != "--check"]
    if len(args) != 1:
        print("usage: fill-missing-translations.py [--check] <Resources dir>")
        return 2
    resources = pathlib.Path(args[0])
    source_dir = resources / (SOURCE_LANGUAGE + ".lproj")
    if not source_dir.is_dir():
        print("error: no %s.lproj in %s" % (SOURCE_LANGUAGE, resources))
        return 1
    source = tables(source_dir)

    incomplete = 0
    for lproj in localizations(resources):
        gaps = missing_keys(source, tables(lproj))
        count = sum(len(entries) for entries in gaps.values())
        if not count:
            continue
        if check:
            incomplete += 1
            sample = sorted(k for entries in gaps.values() for k in entries)[:5]
            print("error: %s is missing %d keys, e.g. %s" % (lproj.name, count, ", ".join(sample)))
            continue
        for (name, suffix), entries in gaps.items():
            path = lproj / (name + suffix)
            merged = load_plist(path) if path.exists() else {}
            merged.update(entries)
            path.write_bytes(plistlib.dumps(merged, fmt=plistlib.FMT_BINARY))
        print("%s: filled %d keys from %s" % (lproj.name, count, SOURCE_LANGUAGE))

    if check:
        if incomplete:
            return 1
        print("Every localization in %s carries all %s keys." % (resources, SOURCE_LANGUAGE))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
