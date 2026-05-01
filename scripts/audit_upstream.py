#!/usr/bin/env python3
"""Audit upstream whisky-app/whisky issues against this fork's evidence.

Fetches open and closed issues from the archived upstream, classifies each
one as addressed-direct, addressed-categorical, wont-fix-out-of-scope,
superseded, or unverified, and writes a diffable index plus a human-readable
report under .planning/audit/. See .planning/audit/README.md.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
AUDIT_DIR = REPO_ROOT / ".planning" / "audit"
SNAPSHOT_PATH = AUDIT_DIR / "snapshot.json"
CLASSIFIED_PATH = AUDIT_DIR / "classified.json"
REPORT_PATH = AUDIT_DIR / "AUDIT_REPORT.md"
OVERRIDES_PATH = AUDIT_DIR / "overrides.json"
LLM_CACHE_PATH = AUDIT_DIR / ".llm_cache.json"
REQUIREMENTS_PATH = REPO_ROOT / ".planning" / "milestones" / "v1.0-REQUIREMENTS.md"

UPSTREAM_REPO = "whisky-app/whisky"
BODY_EXCERPT_BYTES = 2048
LLM_BATCH_SIZE = 20

# ---------------------------------------------------------------------------
# Heuristic configuration
# ---------------------------------------------------------------------------

# Upstream label substrings → internal category codes. Substrings keep this
# robust to minor label drift like "audio: crackling" vs plain "audio".
LABEL_TO_CATEGORY: dict[str, list[str]] = {
    "audio": ["AUDT"],
    "sound": ["AUDT"],
    "graphics": ["GFXC"],
    "rendering": ["GFXC"],
    "gpu": ["GFXC", "STAB"],
    "dxvk": ["GFXC"],
    "controller": ["CTRL"],
    "input": ["CTRL"],
    "gamepad": ["CTRL"],
    "launcher": ["LNCH"],
    "steam": ["LNCH"],
    "epic": ["LNCH"],
    "battle.net": ["LNCH"],
    "crash": ["STAB"],
    "stability": ["STAB"],
    "freeze": ["STAB"],
    "hang": ["STAB", "PROC"],
    "kernel panic": ["STAB"],
    "installer": ["INST"],
    "installation": ["INST"],
    "setup": ["INST"],
    "ui": ["UIUX"],
    "ux": ["UIUX"],
    "configuration": ["CFGF"],
    "config": ["CFGF"],
    "performance": ["GFXC", "STAB"],
    "process": ["PROC"],
}

CATEGORY_KEYWORDS: dict[str, str] = {
    "AUDT": r"\b(audio|sound|crackl\w*|FAudio|dsound|sample[\s-]?rate|bluetooth\s+(?:audio|headset))\b",
    "GFXC": r"\b(DXVK|D3DMetal|wined3d|MoltenVK|shader|black[\s-]?screen|graphic[\s-]?artifact|low[\s-]?fps|texture\s+(?:glitch|corrupt))\b",
    "PROC": r"\b(wineserver|orphan(?:ed)?\s+(?:wine|process)|won['’]?t\s+quit|stuck\s+process|zombie\s+process)\b",
    "STAB": r"\b(crash|access\s+violation|EXC_BAD|IOMFB|segfault|kernel\s+panic|app\s+freeze)\b",
    "GAME": r"\b(won['’]?t\s+(?:start|launch)|game\s+(?:crash|black\s+screen|hang))\b",
    "TRBL": r"\b(how\s+(?:do\s+i|to)|guide|troubleshoot|tutorial|step[\s-]by[\s-]step)\b",
    "LNCH": r"\b(steam(?:webhelper)?|epic\s+games?|EA\s+app|Rockstar|Battle\.?net|launcher\s+(?:download|stuck|crash))\b",
    "CTRL": r"\b(controller|gamepad|xbox|playstation|DualSense|DualShock|joystick)\b",
    "INST": r"\b(install(?:er|ation)?|MSI|setup\.exe|first[\s-]run|onboarding)\b",
    "CFGF": r"\b(WINEPREFIX|environment\s+variable|env[\s-]?var|WINEDLLOVERRIDES|registry\s+(?:key|tweak))\b",
    "UIUX": r"\b(button|sidebar|window|preferences|settings\s+ui|menu\s+bar)\b",
    "FEAT": r"\b(feature\s+request|please\s+add|add\s+support\s+for|proposal)\b",
    "MISC": r"\b(clipboard|temp\s+file|clickonce|appref-ms)\b",
}

OUT_OF_SCOPE_KEYWORDS = re.compile(
    r"\b(Denuvo|EAC|Easy[\s-]?Anti[\s-]?Cheat|BattlEye|"
    r"kernel[\s-]?(?:driver|extension|mode)|"
    r"iOS|iPhone|iPad|Android|"
    r"Wine\s+(?:source|patch)|GPTK\s+source|"
    r"DXMT\s+(?:build|compile))\b",
    re.IGNORECASE,
)

# Out-of-scope categories per .planning/milestones/v1.0-REQUIREMENTS.md.
OOS_CATEGORIES = [
    "wine-source-patches",
    "dxmt-bundling",
    "anti-cheat",
    "kernel-mode",
    "game-specific-wine-patches",
    "full-community-db",
    "mobile-app",
]

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class Issue:
    number: int
    title: str
    state: str
    state_reason: str | None
    labels: list[str]
    comments: int
    reactions_total: int
    locked: bool
    created_at: str
    updated_at: str
    closed_at: str | None
    body_excerpt: str
    html_url: str


@dataclass
class Classification:
    number: int
    status: str
    confidence: str
    matched_categories: list[str] = field(default_factory=list)
    matched_requirements: list[str] = field(default_factory=list)
    evidence: list[dict] = field(default_factory=list)
    rationale: str = ""
    overridden: bool = False
    llm_used: bool = False


# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------


def run(cmd: list[str], capture: bool = True) -> str:
    result = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=capture, text=True, check=False)
    if result.returncode != 0 and capture:
        sys.stderr.write(f"[warn] command failed ({result.returncode}): {' '.join(cmd)}\n")
        sys.stderr.write(result.stderr)
    return result.stdout if capture else ""


def gh_api_paginate(path: str) -> list[dict]:
    raw = run([
        "gh", "api", "-H", "Accept: application/vnd.github+json",
        "--paginate", path,
    ])
    if not raw.strip():
        return []
    # gh --paginate concatenates JSON arrays as a stream of separate arrays.
    # Wrap in brackets and split on ']['.
    chunks = ("[" + raw.replace("][", "],[") + "]") if raw.lstrip().startswith("[") else raw
    try:
        parsed = json.loads(chunks)
    except json.JSONDecodeError:
        # Fall back to line-mode: gh sometimes emits NDJSON when --jq is used.
        parsed = [json.loads(line) for line in raw.splitlines() if line.strip()]
    # Flatten one level if needed.
    flat: list[dict] = []
    for item in parsed:
        if isinstance(item, list):
            flat.extend(item)
        else:
            flat.append(item)
    return flat


def fetch_snapshot() -> list[Issue]:
    sys.stderr.write(f"[info] fetching {UPSTREAM_REPO} issues (paginated)...\n")
    raw = gh_api_paginate(f"/repos/{UPSTREAM_REPO}/issues?state=all&per_page=100")
    issues: list[Issue] = []
    for item in raw:
        if "pull_request" in item:
            continue  # skip PRs
        body = item.get("body") or ""
        reactions = item.get("reactions") or {}
        issues.append(Issue(
            number=item["number"],
            title=item.get("title") or "",
            state=item.get("state") or "open",
            state_reason=item.get("state_reason"),
            labels=[lbl["name"] for lbl in item.get("labels", [])],
            comments=item.get("comments", 0),
            reactions_total=reactions.get("total_count", 0),
            locked=bool(item.get("locked")),
            created_at=item.get("created_at", ""),
            updated_at=item.get("updated_at", ""),
            closed_at=item.get("closed_at"),
            body_excerpt=body[:BODY_EXCERPT_BYTES],
            html_url=item.get("html_url", ""),
        ))
    issues.sort(key=lambda i: i.number)
    return issues


def load_snapshot() -> list[Issue]:
    data = json.loads(SNAPSHOT_PATH.read_text())
    return [Issue(**row) for row in data]


def save_snapshot(issues: list[Issue]) -> None:
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    SNAPSHOT_PATH.write_text(json.dumps([i.__dict__ for i in issues], indent=2))


# ---------------------------------------------------------------------------
# Citation collection
# ---------------------------------------------------------------------------


CITATION_RE = re.compile(r"whisky-app/whisky#(\d+)", re.IGNORECASE)
UPSTREAM_HASH_RE = re.compile(r"\bupstream\s*#(\d+)", re.IGNORECASE)


def collect_citations() -> dict[int, list[dict]]:
    """Return {issue_number: [{type, path, line, excerpt}, ...]}."""
    citations: dict[int, list[dict]] = defaultdict(list)
    grep_paths = [
        "CHANGELOG.md", "README.md", "docs", ".planning",
        "Whisky", "WhiskyKit", "WhiskyCmd", "scripts",
    ]
    existing = [p for p in grep_paths if (REPO_ROOT / p).exists()]
    if existing:
        out = run(["grep", "-rEn", r"whisky-app/whisky#[0-9]+|upstream\s*#[0-9]+",
                   *existing, "--include=*.md", "--include=*.swift", "--include=*.py"])
        for line in out.splitlines():
            # Format: path:line:content
            try:
                path, lineno, content = line.split(":", 2)
            except ValueError:
                continue
            for match in CITATION_RE.finditer(content):
                citations[int(match.group(1))].append({
                    "type": "citation", "path": path, "line": int(lineno),
                    "excerpt": content.strip()[:200],
                })
            for match in UPSTREAM_HASH_RE.finditer(content):
                citations[int(match.group(1))].append({
                    "type": "upstream-citation", "path": path, "line": int(lineno),
                    "excerpt": content.strip()[:200],
                })
    # Also scan git log so commit messages with `Closes whisky-app/whisky#NNN` count.
    log_out = run(["git", "log", "--all", "--format=%H%x09%s%x09%b"])
    for line in log_out.splitlines():
        parts = line.split("\t", 2)
        if len(parts) < 2:
            continue
        sha, subject = parts[0], parts[1]
        body = parts[2] if len(parts) > 2 else ""
        haystack = f"{subject}\n{body}"
        for match in CITATION_RE.finditer(haystack):
            citations[int(match.group(1))].append({
                "type": "git-log", "sha": sha[:8],
                "excerpt": subject[:200],
            })
    return citations


# ---------------------------------------------------------------------------
# v1.0 requirements parsing
# ---------------------------------------------------------------------------


REQ_LINE_RE = re.compile(r"^- \[(x| )\] \*\*([A-Z]{4}-\d+)\*\*:\s*(.+)$")


def load_requirements() -> tuple[dict[str, dict], list[str]]:
    """Return (req_id -> {category, shipped, description}, fully_shipped_categories)."""
    text = REQUIREMENTS_PATH.read_text()
    reqs: dict[str, dict] = {}
    for line in text.splitlines():
        m = REQ_LINE_RE.match(line.strip())
        if not m:
            continue
        shipped = m.group(1) == "x"
        req_id = m.group(2)
        desc = m.group(3).strip()
        cat = req_id.split("-")[0]
        reqs[req_id] = {"category": cat, "shipped": shipped, "description": desc}
    by_cat: dict[str, list[bool]] = defaultdict(list)
    for r in reqs.values():
        by_cat[r["category"]].append(r["shipped"])
    fully_shipped = [c for c, vals in by_cat.items() if all(vals)]
    return reqs, fully_shipped


# ---------------------------------------------------------------------------
# Classifier
# ---------------------------------------------------------------------------


def classify_one(
    issue: Issue,
    citations: dict[int, list[dict]],
    fully_shipped_cats: list[str],
    reqs: dict[str, dict],
) -> Classification:
    # Closed upstream — out of scope for the "what's in our backlog" question,
    # but still worth recording for context. (Note: every issue in the snapshot
    # is `locked` because the upstream repo is archived; ignore that flag.)
    if issue.state == "closed":
        if issue.state_reason == "completed":
            return Classification(
                number=issue.number, status="upstream-fixed", confidence="high",
                rationale="Closed upstream as completed (likely inherited via Wine/runtime upgrades).",
            )
        if issue.state_reason in {"not_planned", "duplicate"}:
            return Classification(
                number=issue.number, status="upstream-declined", confidence="high",
                rationale=f"Closed upstream as {issue.state_reason}.",
            )
        return Classification(
            number=issue.number, status="upstream-closed", confidence="medium",
            rationale="Closed upstream without a state_reason.",
        )

    # 1. Direct citations win.
    if issue.number in citations:
        evidence = citations[issue.number]
        return Classification(
            number=issue.number, status="addressed-direct", confidence="high",
            evidence=evidence,
            rationale=f"Cited {len(evidence)} time(s) in tree/git log.",
        )

    # 2. Out-of-scope keyword sweep — high confidence, can't be overridden by lower steps.
    haystack = f"{issue.title}\n{issue.body_excerpt}"
    if OUT_OF_SCOPE_KEYWORDS.search(haystack):
        return Classification(
            number=issue.number, status="wont-fix-out-of-scope", confidence="high",
            rationale="Matches OOS keyword (anti-cheat / kernel / mobile / Wine source).",
        )

    # 3. Label-based categorization (only this earns addressed-categorical).
    label_cats: set[str] = set()
    for label in issue.labels:
        for needle, cats in LABEL_TO_CATEGORY.items():
            if needle in label.lower():
                label_cats.update(cats)
    shipped_label_cats = label_cats & set(fully_shipped_cats)
    if shipped_label_cats:
        matched_reqs = sorted(rid for rid, info in reqs.items()
                              if info["category"] in shipped_label_cats and info["shipped"])
        return Classification(
            number=issue.number, status="addressed-categorical", confidence="medium",
            matched_categories=sorted(shipped_label_cats),
            matched_requirements=matched_reqs,
            rationale=f"Labels map to category {sorted(shipped_label_cats)} whose v1.0 reqs all shipped.",
        )

    # 4. Keyword regex hints (NOT enough alone — record categories but route to unverified).
    keyword_cats: set[str] = set()
    for cat, pattern in CATEGORY_KEYWORDS.items():
        if re.search(pattern, haystack, re.IGNORECASE):
            keyword_cats.add(cat)

    rationale = (
        f"Keyword hint: {sorted(keyword_cats)}; no label match, no direct citation."
        if keyword_cats
        else "No direct citation, no label match, no keyword match."
    )
    return Classification(
        number=issue.number, status="unverified", confidence="low",
        matched_categories=sorted(keyword_cats),
        rationale=rationale,
    )


def apply_overrides(classifications: list[Classification], overrides: dict) -> None:
    for c in classifications:
        key = str(c.number)
        if key in overrides:
            data = overrides[key]
            c.status = data.get("status", c.status)
            c.confidence = "high"
            c.rationale = data.get("rationale", c.rationale)
            c.overridden = True


# ---------------------------------------------------------------------------
# Optional LLM pass
# ---------------------------------------------------------------------------


def llm_classify(
    issues: list[Issue],
    classifications: list[Classification],
    reqs: dict[str, dict],
) -> int:
    """Run Claude Haiku on issues currently classified as 'unverified'.

    Returns the number of issues whose status changed.
    """
    try:
        import anthropic  # type: ignore
    except ImportError:
        sys.stderr.write("[error] anthropic SDK not installed; pip install -r requirements-audit.txt\n")
        return 0

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        sys.stderr.write("[error] ANTHROPIC_API_KEY not set\n")
        return 0

    by_number = {c.number: c for c in classifications}
    targets = [i for i in issues if by_number[i.number].status == "unverified"]
    if not targets:
        sys.stderr.write("[info] no unverified issues to classify\n")
        return 0

    cache = json.loads(LLM_CACHE_PATH.read_text()) if LLM_CACHE_PATH.exists() else {}
    requirements_hash = hashlib.sha1(
        REQUIREMENTS_PATH.read_text().encode()
    ).hexdigest()[:12]

    client = anthropic.Anthropic(api_key=api_key)
    system_text = build_llm_system_prompt(reqs)

    changed = 0
    pending: list[Issue] = []
    for iss in targets:
        body_hash = hashlib.sha1(iss.body_excerpt.encode()).hexdigest()[:12]
        cache_key = f"{iss.number}:{body_hash}:{requirements_hash}"
        if cache_key in cache:
            decision = cache[cache_key]
        else:
            pending.append(iss)
            continue
        if apply_llm_decision(by_number[iss.number], decision):
            changed += 1

    sys.stderr.write(f"[info] {len(targets)} unverified, {len(pending)} need LLM, {changed} changed from cache\n")

    for batch_start in range(0, len(pending), LLM_BATCH_SIZE):
        batch = pending[batch_start: batch_start + LLM_BATCH_SIZE]
        sys.stderr.write(
            f"[info] LLM batch {batch_start // LLM_BATCH_SIZE + 1}"
            f" / {(len(pending) + LLM_BATCH_SIZE - 1) // LLM_BATCH_SIZE}\n"
        )
        decisions = llm_call(client, system_text, batch)
        for iss in batch:
            decision = decisions.get(str(iss.number)) or decisions.get(iss.number)
            if not decision:
                continue
            body_hash = hashlib.sha1(iss.body_excerpt.encode()).hexdigest()[:12]
            cache_key = f"{iss.number}:{body_hash}:{requirements_hash}"
            cache[cache_key] = decision
            if apply_llm_decision(by_number[iss.number], decision):
                changed += 1
        LLM_CACHE_PATH.write_text(json.dumps(cache, indent=2))

    return changed


def build_llm_system_prompt(reqs: dict[str, dict]) -> str:
    bullet_reqs = "\n".join(
        f"- **{rid}** ({info['category']}, shipped={info['shipped']}): {info['description']}"
        for rid, info in sorted(reqs.items())
    )
    return f"""You are auditing whether the Whisky fork at frankea/Whisky has addressed an upstream issue from the archived whisky-app/whisky.

The fork shipped these v1.0 requirements (all marked shipped=True are live in current main):

{bullet_reqs}

Out-of-scope categories (these should be classified `wont-fix-out-of-scope`):
- Wine/GPTK source code patches
- DXMT compilation/bundling
- Anti-cheat (Denuvo, Easy Anti-Cheat, BattlEye)
- Kernel-mode driver support
- Mobile (iOS/Android)
- Game-specific Wine patches
- Full community compatibility database

For each issue you receive, return a single JSON object per issue with these fields:
- `number` (int, copied verbatim)
- `status` (one of: `addressed-categorical`, `wont-fix-out-of-scope`, `unverified`)
- `matched_requirement_ids` (list of strings; can be empty)
- `confidence` (one of: `high`, `medium`, `low`)
- `rationale` (≤200 characters; concrete reasoning)

Reply with a single JSON object whose keys are issue numbers (as strings) and whose values are the per-issue objects. No prose, no markdown fences, no leading text.
"""


def llm_call(client, system_text: str, batch: list[Issue]) -> dict:
    items = [
        {
            "number": iss.number,
            "title": iss.title,
            "labels": iss.labels,
            "state": iss.state,
            "body": iss.body_excerpt,
        }
        for iss in batch
    ]
    user_msg = (
        "Classify these upstream issues. Reply with a single JSON object keyed by issue number.\n\n"
        f"```json\n{json.dumps(items, indent=2)}\n```"
    )
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=4096,
        system=[{"type": "text", "text": system_text, "cache_control": {"type": "ephemeral"}}],
        messages=[{"role": "user", "content": user_msg}],
    )
    text = "".join(block.text for block in response.content if block.type == "text")
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1].rsplit("```", 1)[0]
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        sys.stderr.write(f"[warn] LLM returned non-JSON: {exc}\n{text[:300]}\n")
        return {}


def apply_llm_decision(c: Classification, decision: dict) -> bool:
    new_status = decision.get("status")
    if new_status not in {"addressed-categorical", "wont-fix-out-of-scope", "unverified"}:
        return False
    if new_status == c.status and not c.matched_requirements:
        # status unchanged but pull in evidence
        c.matched_requirements = decision.get("matched_requirement_ids", [])
        c.rationale = decision.get("rationale", c.rationale)[:240]
        c.llm_used = True
        return False
    c.status = new_status
    c.confidence = decision.get("confidence", "low")
    c.matched_requirements = decision.get("matched_requirement_ids", [])
    c.rationale = decision.get("rationale", c.rationale)[:240]
    c.llm_used = True
    return True


# ---------------------------------------------------------------------------
# Report rendering
# ---------------------------------------------------------------------------


OPEN_STATUSES = [
    "addressed-direct",
    "addressed-categorical",
    "wont-fix-out-of-scope",
    "unverified",
]

CLOSED_STATUSES = [
    "upstream-fixed",
    "upstream-declined",
    "upstream-closed",
]

STATUS_ORDER = OPEN_STATUSES + CLOSED_STATUSES

STATUS_LABEL = {
    "addressed-direct": "Addressed (direct citation)",
    "addressed-categorical": "Addressed (categorical)",
    "wont-fix-out-of-scope": "Won't fix (out of scope)",
    "unverified": "Unverified",
    "upstream-fixed": "Closed upstream — completed",
    "upstream-declined": "Closed upstream — declined",
    "upstream-closed": "Closed upstream — other",
}


def render_report(
    issues: list[Issue],
    classifications: list[Classification],
    reqs: dict[str, dict],
    fully_shipped: list[str],
) -> str:
    by_number = {i.number: i for i in issues}
    by_status = defaultdict(list)
    for c in classifications:
        by_status[c.status].append(c)

    total = len(classifications)
    open_total = sum(1 for i in issues if i.state == "open")
    closed_total = total - open_total

    lines: list[str] = []
    lines.append("# Upstream Issue Audit Report")
    lines.append("")
    lines.append(
        f"Snapshot: **{total}** non-PR issues from `{UPSTREAM_REPO}` — "
        f"**{open_total} open**, **{closed_total} closed**. The headline numbers "
        "below cover the open issues only; the closed buckets are reported "
        "separately for context. Generated by `scripts/audit_upstream.py`. "
        "See `.planning/audit/README.md` for methodology."
    )
    lines.append("")

    # Open-issue summary.
    lines.append("## Open issues — fork's responsibility")
    lines.append("")
    lines.append("| Status | Count | Share |")
    lines.append("|--------|------:|------:|")
    for status in OPEN_STATUSES:
        count = len(by_status[status])
        share = (count / open_total * 100) if open_total else 0
        lines.append(f"| {STATUS_LABEL[status]} | {count} | {share:.1f}% |")
    lines.append(f"| **Total open** | **{open_total}** | 100.0% |")
    lines.append("")

    # Closed-issue summary.
    lines.append("## Closed issues — for context")
    lines.append("")
    lines.append("Already closed in upstream before the archive on 2025-04-09. "
                 "Listed here so the snapshot totals reconcile.")
    lines.append("")
    lines.append("| Status | Count | Share |")
    lines.append("|--------|------:|------:|")
    for status in CLOSED_STATUSES:
        count = len(by_status[status])
        share = (count / closed_total * 100) if closed_total else 0
        lines.append(f"| {STATUS_LABEL[status]} | {count} | {share:.1f}% |")
    lines.append(f"| **Total closed** | **{closed_total}** | 100.0% |")
    lines.append("")

    # By-status × by-category cross-tab (open issues only).
    cats = sorted({c for c in CATEGORY_KEYWORDS} | set(fully_shipped))
    lines.append("## Open status × category")
    lines.append("")
    header = "| Status | " + " | ".join(cats) + " | (none) |"
    lines.append(header)
    lines.append("|" + "---|" * (len(cats) + 2))
    for status in OPEN_STATUSES:
        cells = []
        for cat in cats:
            count = sum(1 for c in by_status[status] if cat in c.matched_categories)
            cells.append(str(count))
        none_count = sum(1 for c in by_status[status] if not c.matched_categories)
        cells.append(str(none_count))
        lines.append(f"| {STATUS_LABEL[status]} | " + " | ".join(cells) + " |")
    lines.append("")

    # Top unaddressed by reactions+comments — open issues only.
    unaddressed = [
        c for c in classifications
        if c.status in {"unverified", "addressed-categorical"} and c.confidence != "high"
    ]
    unaddressed.sort(
        key=lambda c: by_number[c.number].reactions_total + by_number[c.number].comments,
        reverse=True,
    )
    lines.append("## Top 25 unaddressed open issues (by reactions + comments)")
    lines.append("")
    lines.append("Heuristic verdicts only — these are the highest-traffic open issues that are not")
    lines.append("`addressed-direct` and not high-confidence categorical. Likely candidates for")
    lines.append("manual review or override.")
    lines.append("")
    lines.append("| # | Title | Status | Reactions+Comments | URL |")
    lines.append("|---|-------|--------|------:|-----|")
    for c in unaddressed[:25]:
        iss = by_number[c.number]
        traffic = iss.reactions_total + iss.comments
        title = iss.title.replace("|", "\\|")[:80]
        lines.append(
            f"| {iss.number} | {title} | {c.status} | {traffic} | "
            f"[link]({iss.html_url}) |"
        )
    lines.append("")

    # Sample per status.
    lines.append("## Samples per status")
    lines.append("")
    for status in STATUS_ORDER:
        bucket = by_status[status]
        if not bucket:
            continue
        lines.append(f"### {STATUS_LABEL[status]}")
        lines.append("")
        for c in bucket[:3]:
            iss = by_number[c.number]
            lines.append(f"- **#{iss.number}**: {iss.title} — _{c.rationale}_")
            lines.append(f"  - URL: {iss.html_url}")
            if c.evidence:
                paths = ", ".join({ev.get("path") or ev.get("sha", "") for ev in c.evidence})
                lines.append(f"  - Cited in: {paths}")
        lines.append("")

    # Methodology.
    lines.append("## Methodology")
    lines.append("")
    lines.append("Five-step heuristic classifier in `scripts/audit_upstream.py`. See")
    lines.append("`.planning/audit/README.md` for the full pipeline and limitations.")
    lines.append("")
    lines.append(f"Categories with all v1.0 requirements shipped: {', '.join(fully_shipped) or '—'}")
    lines.append("")
    cited_in_changelog = sum(
        1 for c in classifications
        if any(ev.get("path", "").startswith("CHANGELOG") for ev in c.evidence)
    )
    git_log_hits = sum(
        1 for c in classifications
        if any(ev.get("type") == "git-log" for ev in c.evidence)
    )
    overridden = sum(1 for c in classifications if c.overridden)
    llm_touched = sum(1 for c in classifications if c.llm_used)
    lines.append(
        f"Citation breakdown: **{cited_in_changelog}** in CHANGELOG, "
        f"**{git_log_hits}** in git log, "
        f"**{overridden}** manual overrides, "
        f"**{llm_touched}** LLM-classified."
    )
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Diff mode
# ---------------------------------------------------------------------------


def diff_against(ref: str) -> None:
    """Re-run heuristics against a prior commit and print which issues newly classified as addressed."""
    if not CLASSIFIED_PATH.exists():
        sys.stderr.write("[error] no current classified.json; run audit first\n")
        sys.exit(1)
    current = {row["number"]: row for row in json.loads(CLASSIFIED_PATH.read_text())}
    out = run(["git", "show", f"{ref}:.planning/audit/classified.json"])
    if not out.strip():
        sys.stderr.write(f"[error] no classified.json at {ref}\n")
        sys.exit(1)
    prior = {row["number"]: row for row in json.loads(out)}
    flips: list[tuple[int, str, str]] = []
    for num, cur in current.items():
        prev = prior.get(num)
        if not prev or prev["status"] != cur["status"]:
            flips.append((num, prev["status"] if prev else "(absent)", cur["status"]))
    flips.sort()
    print(f"# Diff against {ref}\n")
    print(f"{len(flips)} issues changed status.\n")
    for num, before, after in flips:
        print(f"- #{num}: `{before}` → `{after}`")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def apply_agent_results(
    classifications: list[Classification],
    decisions: dict,
) -> int:
    """Apply pre-computed decisions (e.g. produced by Claude Code subagents).

    `decisions` is keyed by issue number (string or int). Each value is
    `{status, matched_requirement_ids, confidence, rationale}` matching the
    LLM pass schema. Only updates issues currently marked `unverified`.
    """
    by_number = {c.number: c for c in classifications}
    changed = 0
    for key, decision in decisions.items():
        try:
            num = int(key)
        except (TypeError, ValueError):
            continue
        c = by_number.get(num)
        if c is None or c.status != "unverified":
            continue
        if apply_llm_decision(c, decision):
            changed += 1
    return changed


def export_unverified(classifications: list[Classification], issues: list[Issue],
                      out_dir: Path, batch_size: int) -> int:
    """Write the unverified-open issues to chunked JSON files for offline classification."""
    by_number = {i.number: i for i in issues}
    targets = [
        {
            "number": c.number,
            "title": by_number[c.number].title,
            "labels": by_number[c.number].labels,
            "state": by_number[c.number].state,
            "url": by_number[c.number].html_url,
            "body": by_number[c.number].body_excerpt,
            "keyword_hint": c.matched_categories,
        }
        for c in classifications
        if c.status == "unverified"
    ]
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in out_dir.glob("batch_*.json"):
        f.unlink()
    n_batches = 0
    for i in range(0, len(targets), batch_size):
        n_batches += 1
        chunk = targets[i: i + batch_size]
        (out_dir / f"batch_{n_batches:02d}.json").write_text(json.dumps(chunk, indent=2))
    return n_batches


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true",
                        help="Force re-fetch of upstream snapshot")
    parser.add_argument("--llm", action="store_true",
                        help="Run LLM classifier on the unverified bucket via Anthropic API")
    parser.add_argument("--agent-results", metavar="FILE",
                        help="Load pre-computed decisions from JSON file (skips Anthropic API). "
                             "File format: {issue_number: {status, matched_requirement_ids, "
                             "confidence, rationale}}.")
    parser.add_argument("--export-unverified", metavar="DIR",
                        help="Write unverified issues to chunked JSON batches under DIR for "
                             "offline classification by Claude Code subagents, then exit.")
    parser.add_argument("--batch-size", type=int, default=70,
                        help="Issues per batch when --export-unverified is used (default: 70)")
    parser.add_argument("--diff-against", metavar="REF",
                        help="Diff current classifications against a git ref")
    args = parser.parse_args()

    if args.diff_against:
        diff_against(args.diff_against)
        return

    AUDIT_DIR.mkdir(parents=True, exist_ok=True)

    if args.refresh or not SNAPSHOT_PATH.exists():
        issues = fetch_snapshot()
        save_snapshot(issues)
    else:
        issues = load_snapshot()
    sys.stderr.write(f"[info] {len(issues)} issues loaded\n")

    citations = collect_citations()
    sys.stderr.write(f"[info] {len(citations)} unique upstream issue numbers cited in tree+gitlog\n")

    reqs, fully_shipped = load_requirements()
    sys.stderr.write(
        f"[info] {len(reqs)} v1.0 requirements; "
        f"{len(fully_shipped)} categories fully shipped: {fully_shipped}\n"
    )

    classifications = [classify_one(i, citations, fully_shipped, reqs) for i in issues]

    overrides = json.loads(OVERRIDES_PATH.read_text()) if OVERRIDES_PATH.exists() else {}
    apply_overrides(classifications, overrides)
    sys.stderr.write(f"[info] applied {sum(1 for c in classifications if c.overridden)} overrides\n")

    if args.export_unverified:
        n = export_unverified(classifications, issues, Path(args.export_unverified), args.batch_size)
        sys.stderr.write(
            f"[info] wrote {n} batch file(s) of unverified issues to {args.export_unverified}\n"
        )
        return

    if args.agent_results:
        decisions = json.loads(Path(args.agent_results).read_text())
        changed = apply_agent_results(classifications, decisions)
        sys.stderr.write(f"[info] agent-results pass changed {changed} classifications\n")

    if args.llm:
        changed = llm_classify(issues, classifications, reqs)
        sys.stderr.write(f"[info] LLM pass changed {changed} classifications\n")

    counts = Counter(c.status for c in classifications)
    sys.stderr.write(f"[info] final tally: {dict(counts)}\n")

    classifications.sort(key=lambda c: c.number)
    CLASSIFIED_PATH.write_text(
        json.dumps([c.__dict__ for c in classifications], indent=2)
    )
    REPORT_PATH.write_text(render_report(issues, classifications, reqs, fully_shipped))
    sys.stderr.write(f"[done] wrote {CLASSIFIED_PATH} and {REPORT_PATH}\n")


if __name__ == "__main__":
    main()
