#!/usr/bin/env python3
#
# check-placeholder-translations.py
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
# Fails when a dotted key (`audio.findings.fix`) has a localization whose value
# is the key itself. Such a cell is a placeholder that came back from a
# translation export, not a translation: it is marked translated, so the
# build-time fill never replaces it with English, and the raw identifier ends up
# on screen. Remove the cell (the English fallback then applies) and clear it on
# Crowdin so the next export does not bring it back.
#
# Keys that are their own English source ("Open Folder") are skipped, since a
# translation can legitimately equal them.
#
#   ./scripts/check-placeholder-translations.py          exit 1 if any are present
#   ./scripts/check-placeholder-translations.py --strip  remove them in place
#
# --strip edits the catalog line by line (the layout Xcode and Crowdin both
# write) rather than re-serializing it, and refuses to write unless the result
# parses to exactly the original minus the offending cells. The Crowdin sync
# runs it on every export, so cells still stored on Crowdin never come back.

import json
import pathlib
import re
import sys

CATALOG = pathlib.Path(__file__).resolve().parent.parent / "Whisky" / "Localizable.xcstrings"


# `audio.findings.fix`, `pin.error.duplicate.%@`; the part before the first space
# when the key carries format arguments (`audio.history.count %lld`).
IDENTIFIER = re.compile(r"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9_%@-]+)+$")


def is_identifier(key: str) -> bool:
    return IDENTIFIER.match(key.split(" ", 1)[0]) is not None


def string_values(node):
    """Yields every stringUnit value in a localization, including variations."""
    if isinstance(node, dict):
        unit = node.get("stringUnit")
        if isinstance(unit, dict) and "value" in unit:
            yield unit["value"]
        for child in node.values():
            if isinstance(child, dict):
                yield from string_values(child)


def find_offenders(strings):
    offenders = []
    for key, entry in strings.items():
        if not is_identifier(key):
            continue
        stem = key.split(" ", 1)[0]
        for language, localization in entry.get("localizations", {}).items():
            if any(value in (key, stem) for value in string_values(localization)):
                offenders.append((key, language))
    return offenders


def strip(text: str, offenders) -> str:
    """Removes the offending localization blocks from the catalog text."""
    wanted = {}
    for key, language in offenders:
        wanted.setdefault(key, set()).add(language)
    lines = text.split("\n")
    out = []
    current_key = None
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith("    \"") and line.endswith(" : {") and not line.startswith("     "):
            current_key = json.loads(line.strip()[: -len(" : {")])
        if current_key in wanted and line.startswith("        \"") and line.endswith(" : {") \
                and not line.startswith("         "):
            language = json.loads(line.strip()[: -len(" : {")])
            if language in wanted[current_key]:
                end = index + 1
                while lines[end] not in ("        }", "        },"):
                    end += 1
                if lines[end] == "        }" and out and out[-1] == "        },":
                    # The removed block was the last one: drop the comma
                    # the block before it no longer needs.
                    out[-1] = "        }"
                index = end + 1
                continue
        out.append(line)
        index += 1
    return "\n".join(out)


def main() -> int:
    text = CATALOG.read_text(encoding="utf-8")
    catalog = json.loads(text)
    strings = catalog["strings"]
    offenders = find_offenders(strings)

    if "--strip" in sys.argv:
        if not offenders:
            print("No placeholder translations to strip in %d strings" % len(strings))
            return 0
        stripped = strip(text, offenders)
        for key, language in offenders:
            del catalog["strings"][key]["localizations"][language]
        if json.loads(stripped) != catalog:
            print("Stripping changed more than the offending cells; catalog left untouched.")
            return 1
        CATALOG.write_text(stripped, encoding="utf-8")
        print("Stripped %d placeholder translation(s)" % len(offenders))
        return 0

    if offenders:
        print("%d localization(s) are the key itself, not a translation:" % len(offenders))
        for key, language in sorted(offenders):
            print("  %s [%s]" % (key, language))
        print("")
        print("Remove these cells from Whisky/Localizable.xcstrings and clear them on Crowdin.")
        return 1
    print("No placeholder translations in %d strings" % len(strings))
    return 0


if __name__ == "__main__":
    sys.exit(main())
