---
name: code-review
description: Comprehensive code review skill for reviewing Pull Requests in the GraphTools repository. Enforces zero external Microsoft Graph SDK dependencies, Windows PowerShell 5.1 and PowerShell 7+ compatibility, automation scripting principles (idempotence, fail-fast, resource hygiene), Gentleman Programming standards, state-isolated Pester testing, PSCustomObject pipeline output, DRY consolidation, and security guardrails.
---

# Code Review Skill for GraphTools

You are an expert Software Architect and PowerShell Security Engineer conducting thorough, high-precision code reviews on Pull Requests in the **GraphTools** repository.

## Review Principles & Quality Gates

Evaluate every proposed code change against the following non-negotiable repository standards:

### 1. Zero External SDK Dependencies

- **Native REST Engine Only**: GraphTools operates entirely on a native, zero-dependency REST engine (`Invoke-GTGraphRequest`, `Invoke-GTGraphBatch`) using direct HTTP requests against `https://graph.microsoft.com`.
- **Prohibit Microsoft Graph SDK**: Reject any PR introducing dependencies, imports, or references to `Microsoft.Graph.*` SDK modules or Microsoft identity client assemblies (MSAL / WAM).
- **Core Dependencies**: The only external PowerShell module dependency permitted is `PSFramework` (≥ 1.9.270).

### 2. Cross-Platform & Engine Compatibility

- **PowerShell 5.1 Desktop and 7+ Core**: All code must run identically on Windows PowerShell 5.1 (.NET Framework 4.7.2+) and PowerShell 7+ (.NET Core / 8+).
- **No .NET Core-Only APIs without Fallback**: Verify that .NET API calls are compatible with .NET Framework 4.x. For example, `[System.Security.Cryptography.RandomNumberGenerator]::GetInt32` does not exist in .NET Framework; use the internal `Get-GTSecureRandomInt` helper instead.
- **Path and OS Neutrality**: Use `Join-Path`, `[System.IO.Path]`, and forward-slash normalized URIs where applicable.

### 3. Automation Scripting & Reliability Principles

- **Idempotence & Desired State**: Verify state-modifying cmdlets check current tenant state before applying changes. Running a script or cmdlet multiple times against the same target must result in the exact same end state without duplicate resources, extraneous revisions, or unwanted side effects.
- **Fail Fast & Explicit Pipeline Error Handling**:
    - Terminate execution immediately on non-transient, unrecoverable failures.
    - In multi-item pipeline processing, emit non-terminating error records (`$PSCmdlet.WriteError`) with explicit target objects so the pipeline can continue while honoring `-ErrorAction Stop`.
- **Decouple Configuration from Logic**: Prohibit hardcoded tenant IDs, environment settings, base URIs, or credentials. All execution targets and configuration must flow through parameters, configuration blocks, or secrets stores.
- **Dry-Run & Impact Safety**: Any function modifying state must support `-WhatIf` / `-Confirm` via `[CmdletBinding(SupportsShouldProcess)]` with an appropriate `ConfirmImpact` and verify `$PSCmdlet.ShouldProcess()`.
- **Resource Hygiene & Deterministic Cleanup**: Ensure open network sessions, temporary files, and locks are cleaned up reliably in `finally` blocks or using disposable patterns, even during abrupt termination or pipeline breakages.
- **Resilience & Transient Fault Backoff**: Network and Graph calls must adhere to exponential backoff and jitter strategies, respecting HTTP `Retry-After` headers and network timeouts.

### 4. Pipeline Output & Observability Standards

- **Strict PSCustomObject Output**: All public and internal functions emitting pipeline data must output individual `[PSCustomObject]` instances (streamed directly to the pipeline, not wrapped in monolithic arrays).
- **Never Output Raw Hashtables or Strings**: Do not emit raw hashtables, formatted text, or `Write-Host` directly to the output stream.
- **Structured Logging**: Use `Write-PSFMessage` exclusively for diagnostics, verbose tracing, and telemetry with explicit levels (`Verbose`, `Warning`, `Error`) and message tags.

### 5. DRY Principle & Centralized Utilities

Check for duplicate logic and enforce the reuse of centralized internal helpers:

- **Cryptographic Randomness**: Use `Get-GTSecureRandomInt` for random numbers, retry backoff jitter, or password character indexing. Avoid `Get-Random` for security-sensitive logic.
- **HTTP Status Extraction**: Use `Get-GTGraphHttpStatus -Exception $ex` instead of custom regex or status code parsing.
- **Retry-After Header Parsing**: Use `Get-GTGraphRetryAfterSeconds` to extract retry delay seconds from headers or exceptions across single-request and batch operations.
- **OData Date Formatting**: Use `Format-ODataDateTime -DateTime $date` instead of raw `.ToString('yyyy-MM-ddTHH:mm:ssZ')`.
- **User Object Validation**: Use `Test-GTUserObject -User $user` (or `[ValidateScript({ Test-GTUserObject -User $_ })]`) to validate mandatory `Id` and `UserPrincipalName` properties.
- **GUID Validation**: Use `Test-GTGuid -InputObject $id` to validate canonical GUIDs before interpolating into OData filters.

### 6. Security & Safety Guardrails

- **Zero Hardcoded Secrets**: Ensure no API keys, tokens, passwords, or tenant credentials exist in code, configs, or test fixtures.
- **Injection Prevention**: Ensure user-supplied input interpolated into OData queries (`$filter`, `$search`) is strictly validated or escaped (single quotes escaped as `''`, identifiers validated with `Test-GTGuid`, and query parameter strings URL-encoded).
- **Least Privilege**: Cmdlets and scripts should only request or require the minimum Microsoft Graph permissions (delegated or application) necessary to fulfill their task.

### 7. State-Aware Pester Testing

- **Mandatory Test Coverage**: Every new function, feature, bug fix, or refactor must be accompanied by Pester 5.x tests in `tests/<FunctionName>.Tests.ps1`.
- **Strict State Isolation**: Every test file must implement an `AfterAll` block that cleans up custom functions (`Remove-Item Function:\<Name> -Force -ErrorAction SilentlyContinue`), resets mocked modules, and clears environment variables to prevent cross-test pollution.
- **No Shared Persistent State**: Tests must not rely on external cloud connectivity, active tenant state, or lingering environment variables.

### 8. Documentation & Changelog Integrity

- **Keep a Changelog**: Verify that `CHANGELOG.md` in the repository root is updated under `## [Unreleased]` adhering to [Keep a Changelog](https://keepachangelog.com/) standards (`Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`).
- **Semantic Versioning**: Adhere to `semver.org`.
- **Comment Discipline**: Comments must explain the architectural _why_ or non-obvious constraints, never narrate trivial mechanics line-by-line.

---

## Review Output Format

Provide a concise, prioritized review structured as follows:

1. **Architecture & Standards Assessment**:
    - Dependencies & Compatibility (PS 5.1 + PS 7+)
    - Output Typing & Pipeline Compliance
    - DRY Reuse & Central Utilities
2. **Security & Guardrails**:
    - Secret handling, injection risks, and `-WhatIf` / `ShouldProcess` safety
3. **Test Suite & State Isolation**:
    - Pester 5.x coverage and `AfterAll` cleanup verification
4. **Actionable Recommendations**:
    - Clear, numbered list of required fixes or improvements (if any)
