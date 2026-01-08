# Security Policy

## Supported Versions

The following versions of Whisky are currently supported with security updates:

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |
| < Latest | :x:               |

We recommend always using the latest version of Whisky for the best security and feature support.

## Reporting a Vulnerability

If you discover a security vulnerability in Whisky, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities
2. **Email** the maintainer directly at the email associated with [@frankea](https://github.com/frankea)
3. **Include** the following information:
   - Description of the vulnerability
   - Steps to reproduce the issue
   - Potential impact assessment
   - Any suggested fixes (optional)

### What to Expect

- **Acknowledgment**: We will acknowledge receipt of your report within 48 hours
- **Assessment**: We will assess the vulnerability and determine its severity
- **Timeline**: We aim to address critical vulnerabilities within 7 days, and other issues within 30 days
- **Credit**: With your permission, we will credit you in the security advisory

### Scope

This security policy applies to:
- The Whisky application
- WhiskyKit library
- Related command-line tools (WhiskyCmd)
- Build and release infrastructure

### Out of Scope

The following are generally out of scope:
- Vulnerabilities in Wine itself (report to [WineHQ](https://wiki.winehq.org/Bugs))
- Vulnerabilities in DXVK (report to the respective project)
- Issues in third-party dependencies (report upstream, then notify us)

## Security Best Practices for Users

- Only run trusted Windows applications within Whisky
- Keep Whisky and macOS updated to the latest versions
- Be cautious when downloading Windows executables from untrusted sources
- Review application permissions before running unknown software

## Acknowledgments

We thank the security research community for helping keep Whisky secure.
