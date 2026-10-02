# Security Policy

The **GraphTools** project takes security and data confidentiality seriously. This module handles tenant administration, authentication credentials, and privileged operations across Microsoft Entra ID and Microsoft Graph.

---

## Supported Versions

Security patches and bug fixes are provided for the latest minor version release line.

| Version | Supported          | Runtime Environment | Notes |
| :--- | :---: | :--- | :--- |
| **0.27.x** | :white_check_mark: | Windows PowerShell 5.1, PowerShell 7.x | Current stable release line |
| **< 0.27.0** | :x: | Any | Deprecated. Please upgrade to latest. |

---

## Security Architecture & Core Safeguards

GraphTools is designed around strict security principles:

1. **Zero External SDK Dependencies**: Direct HTTP REST engine (`Invoke-GTGraphRequest`, `Invoke-GTGraphBatch`) eliminating untrusted supply-chain risks from third-party client wrappers.
2. **Cryptographically Secure Randomness**: All random number and key/password generation delegates to `Get-GTSecureRandomInt` using `System.Security.Cryptography.RandomNumberGenerator` with rejection sampling to eliminate modulo bias.
3. **Protected Credential Storage**: Opt-in token persistence (`-PersistRefreshToken`) encrypts cached credentials with Windows Data Protection API (DPAPI) on Windows and strict file permissions (`0600`/`0700`) on POSIX environments.
4. **Injection Defense**: All OData filters and user inputs interpolated into Graph queries are strictly validated using canonical GUID validators (`Test-GTGuid`) and OData string escaping.
5. **Impact Protection**: Destructive and state-modifying actions enforce `[CmdletBinding(SupportsShouldProcess)]` with `-WhatIf` / `-Confirm` support.

---

## Reporting a Vulnerability

If you identify a security vulnerability in GraphTools, please notify us responsibly through a private channel.

### Preferred Channel: GitHub Private Vulnerability Reporting

1. Navigate to the [GraphTools Security Advisories](https://github.com/MARCO-K/GraphTools/security/advisories) page.
2. Click **"Report a vulnerability"** to open a private disclosure draft.
3. Provide the details outlined below.

### Alternative Channel: Direct Email

If you cannot submit via GitHub Advisories, contact the project maintainer directly at:
- **Email**: `marco.kleinert@outlook.com`
- **Subject Line**: `[SECURITY VULNERABILITY] GraphTools: <Brief Description>`

---

## What to Include in a Report

To help us triage and resolve the issue quickly, please provide:

- **Component/Function**: Specific cmdlet or internal helper affected (e.g., `Connect-GTGraph`, `New-GTPassword`).
- **Description**: Clear description of the vulnerability, attack vector, and potential impact.
- **Proof of Concept (PoC)**: Minimal, sanitized PowerShell reproduction script or step-by-step reproduction instructions.
- **Impact Assessment**: Evaluation of potential consequences (e.g., credential disclosure, authorization bypass, injection).
- **Environment Details**: PowerShell version (`$PSVersionTable.PSVersion`), OS platform, and GraphTools module version.

> [!CAUTION]
> **Do not include real secrets or tenant credentials in your report.**
> Always use placeholder GUIDs (`00000000-0000-0000-0000-000000000000`) and dummy tokens.

---

## Vulnerability Handling Timeline & SLAs

| Milestone | Target Response SLA | Description |
| :--- | :--- | :--- |
| **Initial Acknowledgement** | Within 48 hours | Confirmation that the report was received and assigned for review. |
| **Triage & Assessment** | Within 5 business days | Technical validation of vulnerability validity, severity scoring (CVSS), and impact scope. |
| **Remediation & Patch** | 7–14 days (Critical/High)<br>30 days (Medium/Low) | Development, state-isolated Pester testing, and release of a patch version. |
| **Public Disclosure** | Coordinated with reporter | Publication of GitHub Security Advisory and attribution in release notes. |

---

## Coordinated Vulnerability Disclosure (CVD)

- **Responsible Disclosure**: Please allow maintainers reasonable time to investigate, remediate, and release a fix before publishing details publicly.
- **Public Disclosure**: Avoid opening public GitHub Issues or PRs containing vulnerability details or active exploit code.
- **Attribution**: We appreciate security research contributions and will gladly credit you in our Security Advisories and [`CHANGELOG.md`](CHANGELOG.md) (unless anonymity is requested).
