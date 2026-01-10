# Release Workflow Documentation

This document describes the process for publishing Wine Libraries and application updates to GitHub Releases and GitHub Pages.

## Overview

The Whisky fork uses the following infrastructure for distribution:

- **GitHub Pages** (`gh-pages` branch): Hosts version metadata and Sparkle appcast
- **GitHub Releases**: Hosts binary assets (Wine Libraries and application builds)

## Wine Libraries Release Process

### Prerequisites

1. Wine/GPTK binaries compiled and packaged as `Libraries.tar.gz`
2. Version number determined (e.g., `2.5.0`)

### Steps

1. **Create GitHub Release**
   ```bash
   # Create a new release tag (e.g., v2.5.0-wine)
   git tag v2.5.0-wine
   git push origin v2.5.0-wine
   ```

2. **Create Release on GitHub**
   - Go to https://github.com/frankea/Whisky/releases/new
   - Select tag: `v2.5.0-wine`
   - Title: `Wine Libraries v2.5.0`
   - Description: Include changelog or notes about Wine version
   - Upload `Libraries.tar.gz` as a release asset
   - Publish release

3. **Update Version Plist on gh-pages**
   ```bash
   git checkout gh-pages
   # Edit WhiskyWineVersion.plist to match the new version
   # Update version numbers:
   #   major: 2
   #   minor: 5
   #   patch: 0
   git add WhiskyWineVersion.plist
   git commit -m "Update WhiskyWine version to 2.5.0"
   git push origin gh-pages
   git checkout main
   ```

4. **Verify Download URL**
   The download URL will be:
   ```
   https://github.com/frankea/Whisky/releases/download/v2.5.0-wine/Libraries.tar.gz
   ```
   
   Note: The version in the URL must match the GitHub Release tag exactly.

## Application Release Process

### Prerequisites

1. Application built and signed (if applicable)
2. Application packaged as `Whisky.app.zip`
3. Sparkle EdDSA signature generated for the release
4. Version number determined (e.g., `1.0.0`)

### Steps

1. **Generate Sparkle Signature**
   ```bash
   # Using Sparkle's generate_appcast tool
   generate_appcast --ed-key-file ~/.ssh/sparkle_eddsa_key.pem path/to/releases/
   ```

2. **Create GitHub Release**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

3. **Create Release on GitHub**
   - Go to https://github.com/frankea/Whisky/releases/new
   - Select tag: `v1.0.0`
   - Title: `Whisky v1.0.0`
   - Description: Include release notes
   - Upload `Whisky.app.zip` as a release asset
   - Publish release

4. **Update appcast.xml on gh-pages**
   ```bash
   git checkout gh-pages
   # Edit appcast.xml to add new item:
   ```
   ```xml
   <item>
       <title>Version 1.0.0</title>
       <sparkle:releaseNotesLink>https://github.com/frankea/Whisky/releases/tag/v1.0.0</sparkle:releaseNotesLink>
       <pubDate>Mon, 01 Jan 2024 00:00:00 +0000</pubDate>
       <enclosure url="https://github.com/frankea/Whisky/releases/download/v1.0.0/Whisky.app.zip"
                  sparkle:version="1.0.0"
                  sparkle:shortVersionString="1.0.0"
                  length="SIZE_IN_BYTES"
                  type="application/octet-stream"
                  sparkle:edSignature="SIGNATURE_FROM_GENERATE_APPCAST"/>
   </item>
   ```
   ```bash
   git add appcast.xml
   git commit -m "Add Whisky v1.0.0 to appcast"
   git push origin gh-pages
   git checkout main
   ```

## Version Numbering

- **Wine Libraries**: Use semantic versioning (e.g., `2.5.0`)
  - Tag format: `v2.5.0-wine` (suffix helps distinguish from app releases)
  - Release title: `Wine Libraries v2.5.0`

- **Application**: Use semantic versioning (e.g., `1.0.0`)
  - Tag format: `v1.0.0`
  - Release title: `Whisky v1.0.0`

## URL Structure

### Wine Libraries
- Version check: `https://frankea.github.io/Whisky/WhiskyWineVersion.plist`
- Download: `https://github.com/frankea/Whisky/releases/download/v{VERSION}/Libraries.tar.gz`

### Application Updates
- Appcast: `https://frankea.github.io/Whisky/appcast.xml`
- Download: `https://github.com/frankea/Whisky/releases/download/v{VERSION}/Whisky.app.zip`

## Testing Checklist

Before publishing a release:

- [ ] Version plist/appcast updated on gh-pages
- [ ] Release created on GitHub with correct tag
- [ ] Assets uploaded to release
- [ ] URLs accessible (test download links)
- [ ] Version check works in application
- [ ] Download succeeds in application
- [ ] Sparkle signature valid (for app releases)

## Troubleshooting

### Download Fails
- Verify release tag matches URL exactly (case-sensitive)
- Check asset filename matches URL (`Libraries.tar.gz` or `Whisky.app.zip`)
- Verify release is published (not draft)

### Version Check Fails
- Verify `WhiskyWineVersion.plist` is accessible at GitHub Pages URL
- Check plist format is valid XML
- Verify version numbers match expected format

### Sparkle Update Check Fails
- Verify `appcast.xml` is accessible at GitHub Pages URL
- Check XML format is valid
- Verify EdDSA signature is correct
- Check `SUPublicEDKey` in Info.plist matches signing key
