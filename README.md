<div align="center">

  # Whisky 🥃
  *Wine but a bit stronger*
  
  ![](https://img.shields.io/github/actions/workflow/status/frankea/Whisky/CI.yml?style=for-the-badge&label=CI)
  [![](https://img.shields.io/codecov/c/github/frankea/Whisky?style=for-the-badge&logo=codecov&label=Coverage)](https://codecov.io/gh/frankea/Whisky)
  [![](https://img.shields.io/github/issues/frankea/Whisky?style=for-the-badge)](https://github.com/frankea/Whisky/issues)
  [![Documentation](https://img.shields.io/badge/Documentation-DocC-blue?style=for-the-badge)](https://frankea.github.io/Whisky/documentation/whiskykit/)
</div>

## Overview

Whisky provides a clean and easy-to-use graphical wrapper for Wine built in native SwiftUI. You can make and manage bottles, install and run Windows apps and games, and unlock the full potential of your Mac with no technical knowledge required.

This repository is a community fork of the original Whisky project, maintained by [@frankea](https://github.com/frankea), aiming to continue development and support for the community.

<img width="650" alt="Config" src="https://github.com/Whisky-App/Whisky/assets/42140194/d0a405e8-76ee-48f0-92b5-165d184a576b">

*Familiar UI that integrates seamlessly with macOS*

<div align="right">
  <img width="650" alt="New Bottle" src="https://github.com/Whisky-App/Whisky/assets/42140194/ed1a0d69-d8fb-442b-9330-6816ba8981ba">

  *One-click bottle creation and management*
</div>

<img width="650" alt="debug" src="https://user-images.githubusercontent.com/42140194/229176642-57b80801-d29b-4123-b1c2-f3b31408ffc6.png">

*Debug and profile with ease*

---

## System Requirements

- **CPU**: Apple Silicon (M-series chips)
- **OS**: macOS Sequoia 15.0 or later

## Installation

### Homebrew

Whisky is available on Homebrew:

```bash
brew install --cask whisky
```

### Manual Installation

Download the latest release from the [Releases page](https://github.com/frankea/Whisky/releases).

## Documentation

WhiskyKit, the core framework powering Whisky, has comprehensive API documentation:

- **[WhiskyKit API Documentation](https://frankea.github.io/Whisky/documentation/whiskykit/)** - Full API reference with usage examples
- **[Getting Started Guide](https://frankea.github.io/Whisky/documentation/whiskykit/gettingstarted)** - Learn how to integrate WhiskyKit
- **[Architecture Overview](https://frankea.github.io/Whisky/documentation/whiskykit/architecture)** - Understand how WhiskyKit components work together

### Troubleshooting

- **[Launcher Troubleshooting](docs/LauncherTroubleshooting.md)** - Fix issues with Steam, Epic, Battle.net, etc.
- **[Stability Troubleshooting](docs/StabilityTroubleshooting.md)** - Diagnose crashes, freezes, reboots, and kernel panics (Issue #40).
- **[Steam Compatibility Guide](docs/SteamCompatibility.md)** - Detailed guide for Steam on Whisky.
- **[Game Support Wiki](https://github.com/frankea/Whisky/wiki/Game-Support)** - Community-maintained game compatibility list.

---

## Credits & Acknowledgments

Whisky is possible thanks to the magic of several projects:

- [msync](https://github.com/marzent/wine-msync) by marzent
- [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) by Gcenx and doitsujin
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) by KhronosGroup
- [Sparkle](https://github.com/sparkle-project/Sparkle) by sparkle-project
- [SemanticVersion](https://github.com/SwiftPackageIndex/SemanticVersion) by SwiftPackageIndex
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) by Apple
- [SwiftTextTable](https://github.com/scottrhoyt/SwiftyTextTable) by scottrhoyt
- [CrossOver](https://www.codeweavers.com/crossover) by CodeWeavers and WineHQ
- D3DMetal by Apple

Special thanks to Gcenx, ohaiibuzzle, Nat Brown, and [Isaac Marovitz](https://github.com/IsaacMarovitz) (original author) for their support and contributions!

---

<table>
  <tr>
    <td>
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="./images/cw-dark.png">
          <img src="./images/cw-light.png" width="500">
        </picture>
    </td>
    <td>
        Whisky doesn't exist without CrossOver. Support the work of CodeWeavers using our <a href="https://www.codeweavers.com/store?ad=1010">affiliate link</a>.
    </td>
  </tr>
</table>
