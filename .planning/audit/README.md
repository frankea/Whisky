# Upstream Issue Audit

A per-issue accounting of how the open issues from the archived upstream
[whisky-app/whisky](https://github.com/whisky-app/whisky) (archived 2025-04-09)
map to fixes, categorical coverage, and explicit non-goals in this fork.

The fork shipped 54 v1.0 requirements covering 10 categories of upstream
issues, but until this tool existed there was no per-issue evidence — the
honest answer to "have we fixed the upstream issues?" was "categorically
yes, individually unverified." This tool replaces that with a per-issue
table.

## Files

| File | Purpose | Tracked |
|------|---------|---------|
| `snapshot.json` | Raw fetched issues from `whisky-app/whisky`. ~5–10 MB. | gitignored |
| `classified.json` | Per-issue enriched index. Deterministically sorted. Diffable. | committed |
| `AUDIT_REPORT.md` | Human-readable summary: counts, top unaddressed, samples, methodology. | committed |
| `overrides.json` | Manual `{number: {status, rationale}}` annotations. Always wins. | committed |
| `.llm_cache.json` | LLM responses keyed by issue body hash + requirements hash. | gitignored |

## Status taxonomy

| Status | Confidence | Meaning |
|--------|------------|---------|
| `addressed-direct` | high | Issue number cited verbatim in CHANGELOG/docs/.planning/code/git log. |
| `addressed-categorical` | medium | Maps via labels/keywords to a satisfied v1.0 requirement category. |
| `wont-fix-out-of-scope` | high | Matches an explicit out-of-scope category (Wine source, anti-cheat, kernel, mobile). |
| `superseded` | medium | Closed upstream as `not_planned`/duplicate, or locked, with no direct citation. |
| `unverified` | low | Heuristics produced no match. The honest bucket. |

## Running

The tool is a single Python 3.12 script.

### Prerequisites

- `gh` CLI authenticated against GitHub (read access is enough; upstream is archived).
- Python 3.12 — `mise install` activates it from the repo's `mise.toml`.
- For the optional `--llm` pass: `pip install -r requirements-audit.txt` and
  `ANTHROPIC_API_KEY` exported.

### Usage

```sh
# Heuristics only (default). Fetches snapshot if absent.
python scripts/audit_upstream.py

# Force a fresh fetch from the upstream API.
python scripts/audit_upstream.py --refresh

# Heuristics + LLM pass on the unverified bucket. Costs ~$2-5 with caching.
ANTHROPIC_API_KEY=sk-... python scripts/audit_upstream.py --llm

# Show "newly addressed since the given ref".
python scripts/audit_upstream.py --diff-against app-v3.0.1
```

The tool is idempotent and the outputs sort deterministically, so re-runs
produce diffable changes.

## Methodology

The classifier runs in five steps. Higher-confidence verdicts win.

1. **Direct citation grep** of CHANGELOG, docs/, .planning/, source trees, and
   `git log --all` for the literal pattern `whisky-app/whisky#NNN`.
2. **Label-based categorization** via a hand-maintained map from upstream
   labels to internal v1.0 categories (CFGF, GFXC, AUDT, PROC, STAB, GAME,
   TRBL, LNCH, CTRL, INST, UIUX, FEAT, MISC). If the issue's labels match a
   category whose v1.0 reqs are fully shipped, it's `addressed-categorical`.
3. **Keyword regex** over `title + body_excerpt` against the same category
   map plus an out-of-scope set (Denuvo, EAC, kernel, iOS, Android, etc.).
4. **State-based fallback**: closed-as-`not_planned` → `superseded`.
5. **Default** → `unverified`.

`overrides.json` is loaded last and always wins. Use it for issues fixed by
upstream Wine/MoltenVK/DXVK upgrades that the fork inherited but didn't
explicitly cite.

## Limitations

- **Silent fixes** read as `unverified` until cited or overridden. Going
  forward, prefer `Closes whisky-app/whisky#NNN` in commit messages — the
  citation grep covers `git log --all`.
- **Wine/MoltenVK uplift fixes** are invisible to heuristics; the LLM may
  catch some, otherwise rely on `overrides.json`.
- **Body excerpts capped at 2 KB.** Long bug reports lose context; the LLM
  pass can fetch full bodies for borderline cases on demand.
- **No upstream-PR correlation.** Doesn't check upstream PRs that closed
  issues before archive — those are upstream-fixed, separate question.
- **Label drift.** Upstream labels are inconsistent; categorization is best
  effort.

The headline counts in `AUDIT_REPORT.md` are honest about every status's
confidence, including the size of the `unverified` bucket. That's the
point.
