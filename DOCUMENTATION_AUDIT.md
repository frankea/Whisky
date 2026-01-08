# Documentation Audit Report

**Repository:** frankea/Whisky (community fork)  
**Original Repository:** IsaacMarovitz/Whisky  
**Audit Date:** 2026-01-08

---

## Executive Summary

This audit identifies all documentation and configuration references that need updating to reflect the fork transition from the original Whisky project to this community-maintained fork. Changes are prioritized by impact on functionality and user experience.

---

## 🔴 CRITICAL Priority (Broken Functionality / Incorrect Maintainer Info)

### 1. README.md - Build Badge URL (ALREADY FIXED in PR #30)
| Attribute | Details |
|-----------|---------|
| **File** | [`README.md`](README.md:6) |
| **Current** | `https://img.shields.io/github/actions/workflow/status/IsaacMarovitz/Whisky/SwiftLint.yml` |
| **Recommended** | `https://img.shields.io/github/actions/workflow/status/frankea/Whisky/SwiftLint.yml` |
| **Status** | ✅ Fixed in PR #30 |

### 2. .github/FUNDING.yml - Sponsor Info (ALREADY FIXED in PR #30)
| Attribute | Details |
|-----------|---------|
| **File** | [`.github/FUNDING.yml`](.github/FUNDING.yml:3) |
| **Current** | `ko_fi: isaacmarovitz` |
| **Recommended** | `github: frankea` |
| **Status** | ✅ Fixed in PR #30 |

### 3. WhiskyKit Bundle Identifier - Default Fallback
| Attribute | Details |
|-----------|---------|
| **File** | [`WhiskyKit/Sources/WhiskyKit/Extensions/Bundle+Extensions.swift`](WhiskyKit/Sources/WhiskyKit/Extensions/Bundle+Extensions.swift:23) |
| **Current** | `"com.isaacmarovitz.Whisky"` |
| **Recommended** | `"com.frankea.Whisky"` or keep as-is for compatibility |
| **Justification** | This is a fallback value when bundle identifier is unavailable. Changing it may affect existing user data paths. Consider impact before changing. |
| **Status** | ⚠️ Needs decision - code change, may affect data migration |

---

## 🟠 HIGH Priority (Outdated URLs Affecting User Experience)

### 4. Whisky/Views/WhiskyApp.swift - Help Menu GitHub Link
| Attribute | Details |
|-----------|---------|
| **File** | [`Whisky/Views/WhiskyApp.swift`](Whisky/Views/WhiskyApp.swift:112) |
| **Current** | `"https://github.com/Whisky-App/Whisky"` |
| **Recommended** | `"https://github.com/frankea/Whisky"` |
| **Justification** | Help → GitHub menu item opens wrong repository. Users cannot find correct issue tracker or documentation. |
| **Status** | ✅ Fixed - GitHub link updated to frankea/Whisky |

### 5. Whisky/Views/WhiskyApp.swift - Help Menu Items Restructured
| Attribute | Details |
|-----------|---------|
| **File** | [`Whisky/Views/WhiskyApp.swift`](Whisky/Views/WhiskyApp.swift:103) |
| **Changes** | - Removed "Website" menu item (getwhisky.app domain)<br>- Removed "Discord" menu item (no Discord server)<br>- Added "Report Issues" menu item linking to GitHub Issues |
| **Justification** | Website/Discord links pointed to original project. Replaced with GitHub Issues for support. |
| **Status** | ✅ Fixed - Help menu restructured |

### 6. Whisky/Info.plist - Sparkle Update Feed URL
| Attribute | Details |
|-----------|---------|
| **File** | [`Whisky/Info.plist`](Whisky/Info.plist:57) |
| **Current** | `https://data.getwhisky.app/appcast.xml` |
| **Recommended** | Set up fork-specific update infrastructure OR disable auto-updates |
| **Justification** | Auto-updates would pull from original project, potentially overwriting fork changes. Critical for distribution. |
| **Status** | ❌ Needs infrastructure + code change |

### 7. WhiskyWineInstaller.swift - Wine Version Check URL
| Attribute | Details |
|-----------|---------|
| **File** | [`WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift`](WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift:64) |
| **Current** | `https://data.getwhisky.app/Wine/WhiskyWineVersion.plist` |
| **Recommended** | Set up fork-specific Wine distribution OR keep using original (with attribution) |
| **Justification** | Wine version checks depend on original project's infrastructure. If it shuts down, Wine updates break. |
| **Status** | ⚠️ Needs infrastructure decision |

### 8. WhiskyWineDownloadView.swift - Wine Libraries Download URL
| Attribute | Details |
|-----------|---------|
| **File** | [`Whisky/Views/Setup/WhiskyWineDownloadView.swift`](Whisky/Views/Setup/WhiskyWineDownloadView.swift:68) |
| **Current** | `https://data.getwhisky.app/Wine/Libraries.tar.gz` |
| **Recommended** | Set up fork-specific hosting OR document dependency on original infrastructure |
| **Justification** | Core functionality depends on external infrastructure owned by original project. |
| **Status** | ⚠️ Needs infrastructure decision |

---

## 🟡 MEDIUM Priority (Cosmetic / Clarity Improvements)

### 9. README.md - Screenshot URLs (No Change Needed)
| Attribute | Details |
|-----------|---------|
| **File** | [`README.md`](README.md:14) |
| **Current** | `https://github.com/Whisky-App/Whisky/assets/...` |
| **Recommended** | Keep as-is - these are CDN links that work regardless of repo ownership |
| **Justification** | GitHub asset URLs remain accessible even after fork. No functional impact. |
| **Status** | ✅ No action needed |

### 10. README.md - Wiki Link (ALREADY FIXED in PR #30)
| Attribute | Details |
|-----------|---------|
| **File** | [`README.md`](README.md:47) |
| **Current** | `https://github.com/IsaacMarovitz/Whisky/wiki/Game-Support` |
| **Recommended** | `https://github.com/frankea/Whisky/wiki/Game-Support` |
| **Status** | ✅ Fixed in PR #30 (but wiki needs to be created/migrated) |

### 11. .github/ISSUE_TEMPLATE/config.yml - Discord Link Removed
| Attribute | Details |
|-----------|---------|
| **File** | [`.github/ISSUE_TEMPLATE/config.yml`](.github/ISSUE_TEMPLATE/config.yml:3) |
| **Changes** | Discord support link replaced with GitHub Issues link |
| **Justification** | Fork does not have a Discord server. GitHub Issues is now the primary support channel. |
| **Status** | ✅ Fixed - Discord link removed, GitHub Issues added |

### 12. .github/ISSUE_TEMPLATE/bug.yml - Whisky Version Dropdown
| Attribute | Details |
|-----------|---------|
| **File** | [`.github/ISSUE_TEMPLATE/bug.yml`](.github/ISSUE_TEMPLATE/bug.yml:39-40) |
| **Current** | Version options: "2.3.2", "<2.3.2" |
| **Recommended** | Update to reflect fork's current version numbering |
| **Justification** | Version dropdown should match fork's release versions for accurate bug reports. |
| **Status** | ⚠️ Needs update when releasing |

### 13. .github/ISSUE_TEMPLATE/bug.yml - macOS Version Dropdown
| Attribute | Details |
|-----------|---------|
| **File** | [`.github/ISSUE_TEMPLATE/bug.yml`](.github/ISSUE_TEMPLATE/bug.yml:48) |
| **Current** | Only "Sonoma (macOS 14)" |
| **Recommended** | Add "Sequoia (macOS 15)" and other supported versions |
| **Justification** | macOS Sequoia is now available; template is outdated. |
| **Status** | ❌ Needs update |

---

## 📋 Files Reviewed - No Changes Needed

| File | Status | Notes |
|------|--------|-------|
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | ✅ OK | No repository-specific URLs |
| [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) | ✅ Updated | Discord link replaced with GitHub Issues |
| [`LICENSE`](LICENSE) | ✅ OK | GPL-3.0 - no attribution changes needed for fork |
| [`.github/workflows/CI.yml`](.github/workflows/CI.yml) | ✅ OK | No hardcoded URLs to original repo |
| [`.github/workflows/Release.yml`](.github/workflows/Release.yml) | ✅ Updated | Discord webhook removed |
| [`.github/workflows/AutoAssign.yml`](.github/workflows/AutoAssign.yml) | ✅ OK | Uses `afranke` (correct maintainer handle) |
| [`.github/dependabot.yml`](.github/dependabot.yml) | ✅ OK | No external dependencies |
| [`.github/ISSUE_TEMPLATE/feature-request.yml`](.github/ISSUE_TEMPLATE/feature-request.yml) | ✅ OK | No URLs or version info |

---

## 📝 Missing Documentation (Recommended Additions)

### 1. SECURITY.md
| Recommendation | Details |
|---------------|---------|
| **Purpose** | Provide security vulnerability reporting process |
| **Content** | Contact information, responsible disclosure policy |
| **Priority** | Medium |

### 2. Wiki Migration/Creation
| Recommendation | Details |
|---------------|---------|
| **Purpose** | README links to `frankea/Whisky/wiki/Game-Support` but wiki doesn't exist |
| **Content** | Migrate or recreate game compatibility documentation |
| **Priority** | High (link is broken until created) |

### 3. Fork Notice in App "About" Dialog
| Recommendation | Details |
|---------------|---------|
| **Purpose** | In-app acknowledgment of fork status |
| **Location** | Help menu → About Whisky dialog |
| **Priority** | Low |

---

## 🔧 Infrastructure Dependencies

The following external URLs depend on original project infrastructure (`data.getwhisky.app`):

| Purpose | URL | Risk Level |
|---------|-----|------------|
| Auto-update feed | `https://data.getwhisky.app/appcast.xml` | 🔴 Critical |
| Wine version check | `https://data.getwhisky.app/Wine/WhiskyWineVersion.plist` | 🔴 Critical |
| Wine libraries | `https://data.getwhisky.app/Wine/Libraries.tar.gz` | 🔴 Critical |
| Website | `https://getwhisky.app/` | 🟡 Medium |

**Recommendation:** Establish fork-specific infrastructure or formally document the dependency on original project's infrastructure with a fallback plan.

---

## Summary Action Items

### Immediate Actions (PR #30 - Completed)
- [x] Update README badge URL
- [x] Update README wiki link
- [x] Update README with fork notice
- [x] Update FUNDING.yml

### Additional Changes (Included in PR #30)
- [x] Update Help menu GitHub link in WhiskyApp.swift
- [x] Remove Discord help menu item, add Report Issues item
- [x] Remove website help menu item
- [x] Add help.issues localization key
- [x] Update bug report template macOS versions (added Sequoia)
- [x] Add SECURITY.md
- [x] Remove Discord badge from README (replaced with GitHub Issues badge)
- [x] Update CODE_OF_CONDUCT.md Discord link to GitHub Issues
- [x] Update issue template config.yml Discord to GitHub Issues
- [x] Remove Discord webhook from Release.yml workflow

### Short-term Actions (New PRs Needed)
1. [ ] Create Wiki with Game-Support page

### Long-term Decisions Required
1. [ ] Decide on auto-update infrastructure (keep original, fork, or disable)
2. [ ] Decide on Wine distribution strategy
3. [ ] Decide on bundle identifier for new installations

---

*Generated by Documentation Audit - 2026-01-08*
