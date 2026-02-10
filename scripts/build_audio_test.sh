#!/bin/bash
#
# build_audio_test.sh
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
# Cross-compiles whisky_audio_test.c into WhiskyAudioTest.exe using MinGW.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${SCRIPT_DIR}/whisky_audio_test.c"
OUTPUT="${SCRIPT_DIR}/WhiskyAudioTest.exe"
DEST_DIR="${SCRIPT_DIR}/../Whisky/Resources"
COMPILER="x86_64-w64-mingw32-gcc"

if ! command -v "${COMPILER}" &>/dev/null; then
    echo "Error: ${COMPILER} not found."
    echo "Install MinGW with: brew install mingw-w64"
    exit 1
fi

echo "Compiling WhiskyAudioTest.exe..."
"${COMPILER}" -o "${OUTPUT}" "${SOURCE}" -lwinmm -lm

echo "Build successful: ${OUTPUT}"

if [ -d "${DEST_DIR}" ]; then
    cp "${OUTPUT}" "${DEST_DIR}/WhiskyAudioTest.exe"
    echo "Copied to ${DEST_DIR}/WhiskyAudioTest.exe"
else
    echo "Warning: ${DEST_DIR} does not exist. Copy manually to Whisky/Resources/."
fi
