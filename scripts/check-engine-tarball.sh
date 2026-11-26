#!/usr/bin/env bash
# Checks a Wine Libraries tarball before it is published or promoted.
#
#   scripts/check-engine-tarball.sh CANDIDATE.tar.gz [PREVIOUS.tar.gz [EXPECTED_REGEX]]
#
# 1. The build's optimization level, from `buildOptimization` in the tarball's
#    WhiskyWineVersion.plist, must be -O3. v4.8.5 was built at -O2 against a
#    v4.8.3 built at -O3, which changed every DLL, and it broke games that ran
#    on v4.8.3 (#420). Builds from before the mirror stamped the level have no
#    key; those fail unless ALLOW_UNSTAMPED=1, set only after reading
#    "optimisation: -O3" in the build log yourself.
# 2. With PREVIOUS, every file whose size differs from PREVIOUS is listed, and
#    any not matching EXPECTED_REGEX (an extended regex over the path inside the
#    tarball) fails the check. A build that is "the previous engine plus a few
#    patches" should only differ in the files those patches touch, for example
#    'gdi32|ws2_32|ntdll|wow64|WhiskyWineVersion.plist'.
#
# Exits 0 when every check passes, 1 otherwise.

set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 3 ]; then
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi

candidate=$1
previous=${2:-}
expected=${3:-'WhiskyWineVersion\.plist$'}
status=0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

plist="$work/WhiskyWineVersion.plist"
tar -xzOf "$candidate" Libraries/WhiskyWineVersion.plist > "$plist"
opt=$(/usr/libexec/PlistBuddy -c "Print :buildOptimization" "$plist" 2>/dev/null || true)
version=$(/usr/libexec/PlistBuddy -c "Print :version" "$plist" | awk '/= /{print $3}' | paste -sd. -)
echo "version: $version"
if [ "$opt" = "-O3" ]; then
    echo "optimization: $opt (ok)"
elif [ -z "$opt" ] && [ "${ALLOW_UNSTAMPED:-}" = 1 ]; then
    echo "optimization: not recorded (ALLOW_UNSTAMPED=1: confirm 'optimisation: -O3' in the build log)"
elif [ -z "$opt" ]; then
    echo "optimization: not recorded (FAIL: rebuild with a mirror that stamps buildOptimization,"
    echo "  or confirm 'optimisation: -O3' in the build log and rerun with ALLOW_UNSTAMPED=1)"
    status=1
else
    echo "optimization: $opt (FAIL: release builds are -O3; dispatch with opt=release)"
    status=1
fi

if tar -tzf "$candidate" | grep -q '/\._'; then
    echo "AppleDouble entries: present (FAIL: repack with COPYFILE_DISABLE=1)"
    status=1
fi

if [ -n "$previous" ]; then
    sizes() {
        tar -tvzf "$1" | awk '$1 ~ /^-/ {size=$5; $1=$2=$3=$4=$5=$6=$7=$8=""; sub(/^ +/, ""); print $0 "\t" size}' | sort
    }
    sizes "$candidate" > "$work/candidate.txt"
    sizes "$previous" > "$work/previous.txt"
    changed=$(join -t $'\t' "$work/previous.txt" "$work/candidate.txt" | awk -F'\t' '$2 != $3 {print $1}')
    added=$(comm -13 <(cut -f1 "$work/previous.txt") <(cut -f1 "$work/candidate.txt"))
    removed=$(comm -23 <(cut -f1 "$work/previous.txt") <(cut -f1 "$work/candidate.txt"))
    count=$(printf '%s\n' "$changed" | grep -c . || true)
    echo "files that changed size against $(basename "$previous"): $count"
    unexpected=$(printf '%s\n' "$changed" | grep -Ev "$expected" | grep . || true)
    if [ -n "$unexpected" ]; then
        echo "FAIL: changed outside '$expected' (first 20):"
        printf '%s\n' "$unexpected" | head -20 | sed 's/^/  /'
        status=1
    else
        printf '%s\n' "$changed" | grep . | sed 's/^/  /' || true
    fi
    if [ -n "$added" ] || [ -n "$removed" ]; then
        echo "FAIL: the file list differs:"
        printf '%s\n' "$added" | grep . | sed 's/^/  + /' || true
        printf '%s\n' "$removed" | grep . | sed 's/^/  - /' || true
        status=1
    fi
fi

[ "$status" -eq 0 ] && echo "PASS" || echo "FAILED"
exit "$status"
