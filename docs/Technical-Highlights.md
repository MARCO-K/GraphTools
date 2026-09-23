# GraphTools Technical Highlights

## 🏗️ Technical Architecture

### Module Structure

GraphTools is built as a PowerShell script module with a clean, modular architecture designed for enterprise security operations:

```
GraphTools/
├── GraphTools.psd1          # Module manifest with dependency management
├── GraphTools.psm1          # Module loader with automatic function discovery
├── functions/               # Public cmdlets (Connect-GTGraph, Get-GTUser, etc.)
├── internal/
│   └── functions/          # Private helpers (Invoke-GTGraphRequest, Get-GTCachedGraphToken, etc.)
├── tests/                   # Pester test suite (40 test files)
├── docs/                    # Comprehensive documentation
├── data/                    # Offline metadata catalogs (DevX permissions fixture)
└── en-us/                   # Localization and help files
```

### PowerShell Standards Compliance

- **PowerShell Version Support**: 5.1+ and 7.0+ (strictly verified across engines)
- **Cmdlet Naming**: Approved verbs with `GT` prefix (`Get-GTUser`, `Connect-GTGraph`, `Disable-GTUser`)
- **Parameter Binding**: Full `[CmdletBinding()]` support with pipeline input
- **Comment-Based Help**: Complete help documentation for all public functions
- **Error Handling**: Centralized error responses via `Get-GTGraphErrorDetails`
- **Output Contracts**: Pure `[PSCustomObject]` pipeline emission

## 🔧 Core Technical Features

### Zero-Dependency Microsoft Graph REST Engine

GraphTools has completely eliminated external runtime dependencies on the `Microsoft.Graph.*` SDK, executing all operations through native .NET and PowerShell REST primitives:

**Authentication & Token Management**:

- **RFC 7523 Certificate Flow**: Signs RS256 JWT client assertions using native .NET cryptography (`RSACertificateExtensions`) directly from `Cert:\LocalMachine\My` or `Cert:\CurrentUser\My` (hardware/DPAPI protected).
- **Client Secret Credentials**: Native client credentials token acquisition.
- **In-Memory Token Caching**: Sliding 5-minute expiration buffer (`$script:GTTokenCache`) prevents token endpoint rate limits (HTTP 429) and provides 0ms token acquisition for cache hits.
- **Unified Connection Cmdlets**: `Connect-GTGraph`, `Disconnect-GTGraph`, `Get-GTConnection`.

**Central REST Execution (`Invoke-GTGraphRequest`)**:

- **Multi-Endpoint Support**: Seamless execution against production (`v1.0`) and preview (`beta`) endpoints.
- **Automatic Pagination**: `@odata.nextLink` traversal with `-All`, accumulating results efficiently using `List[object]`.
- **Throttling & Retry Engine**: Catches HTTP `429` and `503`, parses `Retry-After` headers, and executes exponential backoff with jitter.
- **JSON Batching (`Invoke-GTGraphBatch`)**: Combines up to 20 subrequests into a single `POST /$batch` roundtrip, with automatic chunking for arbitrary request volumes.
- **Detailed Architecture Specification**: See [[Zero-Dependency-REST-Architecture]] and [[Connect-GTGraph]].

### Advanced Parameter Design

**Flexible User Identification**:

```powershell
# Multiple aliases supported for user parameters
[Alias('UPN','UserPrincipalName','Users','User','UserName','UPNName')]
[string[]]$UPN
```

**Pipeline Support**:

- **ValueFromPipeline**: Accept input from pipeline
- **Batch Processing**: Efficient handling of multiple objects
- **Streaming Output**: Real-time results without memory exhaustion

**Validation Framework**:

- **UPN Regex Validation**: `$script:GTValidationRegex.UPN = '^[^@\s]+@[^@\s]+\.[^@\s]+$'`
- **GUID Validation**: Prevents injection attacks in OData filters
- **Parameter Sets**: Context-aware parameter validation

## 🛡️ Security & Reliability

### Input Validation & Sanitization

**Injection Attack Prevention**:

- **OData Filter Safety**: All user input sanitized before filter interpolation
- **Regex Validation**: Strict pattern matching for user identifiers
- **GUID Verification**: Internal `Test-GTGuid` function for ID validation

**Protected Functions**:

```powershell
# Functions with built-in GUID validation
- Disable-GTUserDevice
- Remove-GTUserRoleAssignments
- Remove-GTUserDelegatedPermissionGrants
- Remove-GTPIMRoleEligibility
- Remove-GTUserAccessPackageAssignments
```

### Error Handling Architecture

**Centralized Error Processing**:

```powershell
# Get-GTGraphErrorDetails helper function
$err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Users'
Write-PSFMessage -Level $err.LogLevel -Message "Failed: $($err.Reason)"
```

**Structured Error Responses**:

```powershell
@{
    User             = 'user@contoso.com'
    Status           = 'Failed'
    TimeUtc          = '2025-01-14T12:30:00.000Z'
    HttpStatus       = 404
    Reason           = 'User not found'
    ExceptionMessage = $_.Exception.Message
}
```

**HTTP Status Code Extraction**:

- **404/403**: Generic messages prevent account enumeration
- **429**: Throttling guidance with retry recommendations
- **400/500**: Detailed error context for debugging

## 📊 Data Processing & Analytics

### Risk Scoring Engine

**Multi-Dimensional Risk Assessment**:

```powershell
$RiskEngine = @{
    'RoleManagement.ReadWrite.Directory' = @{
        Score = 10; Level = 'Critical'; Impact = 'Privilege Escalation';
        Desc = 'Can promote self to Global Admin'
    }
    'Directory.ReadWrite.All' = @{
        Score = 9; Level = 'Critical'; Impact = 'Tenant Destruction';
        Desc = 'Can delete users, groups, and apps'
    }
}
```

**Impact Categories**:

- **Privilege Escalation**: Role elevation capabilities
- **Data Exfiltration**: Information disclosure risks
- **Data Integrity**: Modification/deletion threats
- **Tenant Destruction**: Organization-wide impact
- **Impersonation**: Identity spoofing risks

### Forensic Context Collection

**Comprehensive Audit Trail**:

- **Who**: Permission grantor identification
- **When**: Timestamp analysis with UTC standardization
- **What**: Permission scope and risk assessment
- **How**: Grant mechanism (admin consent, user consent)
- **Usage**: Activity monitoring and dormant account detection

### Performance Optimizations

**Efficient Data Retrieval**:

- **Targeted Filtering**: AppId-specific queries reduce API calls
- **Pagination Handling**: Automatic `$all` parameter management
- **Caching Strategies**: Microsoft Graph role cache, user lookup cache
- **Batch Operations**: Pipeline accumulation for bulk processing

## 🔄 Automation & Integration

### Pipeline Architecture

**Begin/Process/End Pattern**:

```powershell
begin {
    # Session verification & REST invoker preparation
    $connection = Get-GTConnection
    if (-not $connection -or -not $connection.Connected) {
        Connect-GTGraph
    }
}
process {
    # Direct REST invocation with automatic bearer injection, paging, and retry
    Invoke-GTGraphPagedRequest -Endpoint "users/$($_.Id)/transitiveMemberOf"
}
end {
    # Pipeline cleanup and emission of pure [PSCustomObject] records
}
```

**Memory-Efficient Processing**:

- **Streaming Input**: Seamless pipeline binding (`ValueFromPipeline`, `ValueFromPipelineByPropertyName`)
- **Lazy Evaluation & Paging**: `@odata.nextLink` traversal with memory-optimized collection (`System.Collections.Generic.List[object]`)
- **Correlated Batching**: `Invoke-GTGraphBatch` enables up to 20 subrequests per single HTTP roundtrip

### Zero-Dependency Lifecycle Management

**Elimination of External SDKs**:

- **Zero Runtime Dependencies**: No gigabytes of external `Microsoft.Graph.*` modules or multi-minute module installation overhead in CI/CD or cloud runbooks.
- **Pure .NET Crypto & REST**: In-memory token acquisition and REST invocation powered entirely by PowerShell primitives and .NET Standard cryptographic libraries.

**Connection & Session Reuse**:

- **Sliding In-Memory Cache**: Active bearer tokens are cached in-memory with a 5-minute pre-expiry buffer (`$script:GTTokenCache`), preventing redundant authentication calls.
- **Automatic Token Refresh**: Transparently re-authenticates upon expiry without user or script intervention.
- **Enterprise Identity Ready**: Supports Entra ID App Registrations with certificate thumbprints, raw certificates, client secrets, and existing bearer tokens.

## 📈 Advanced Analytics Features

### Conditional Access Policy Analysis

**Policy Gap Detection**:

- **Control Evaluation**: Grant controls, session controls, authentication strength
- **Targeting Analysis**: User/group/role/application scope validation
- **State Assessment**: Enabled, disabled, and reporting-only policies
- **Risk Prioritization**: Critical gaps vs informational findings

**Break Glass Auditing**:

- **Emergency Account Validation**: Exclusion verification across all policies
- **Risk Assessment**: BLOCK policies flagged as Critical risks
- **UPN Resolution**: Object ID mapping for accurate policy checking

### Application Permission Risk Analysis

**Dual Permission Model Support**:

- **App-Only Permissions**: Service principal app role assignments
- **Delegated Permissions**: OAuth2 permission grants with consent types

**Advanced Filtering**:

- **Permission Type**: AppOnly, Delegated, or Both
- **Risk Level**: Critical, High, Medium filtering
- **Application Targeting**: Specific app analysis with optimized queries
- **Custom Risk Definitions**: User-defined high-risk scopes

### Audit Log Integration

**Unified Audit Log Queries**:

- **Time-Based Filtering**: Start/end date parameters with OData formatting
- **Multi-Criteria Search**: Operations, users, IP addresses, record types
- **Result Processing**: Structured output with activity details
- **Performance Optimization**: Efficient pagination and filtering

## 🧪 Testing & Quality Assurance

### Comprehensive Test Suite

**Pester Framework Integration**:

- **Unit Tests**: Parameter validation, business logic verification
- **Mock Integration**: Microsoft Graph API simulation
- **Pipeline Testing**: Input/output validation
- **Error Scenario Coverage**: Exception handling verification

**Test Organization**:

```powershell
Describe "Get-GTRiskyAppPermissionReport" {
    BeforeAll {
        Mock Get-GTConnection { [PSCustomObject]@{ Connected = $true; TenantId = 'fa8b2a79-cd59-468b-a25d-a6fef0b4dad1' } }
        . "$PSScriptRoot/../functions/Get-GTRiskyAppPermissionReport.ps1"
    }

    Context "Parameter Validation" {
        It "should validate PermissionType parameter" {
            { Get-GTRiskyAppPermissionReport -PermissionType "Invalid" } | Should -Throw
        }
    }
}
```

### CI/CD Integration

**PSScriptAnalyzer Validation**:

```yaml
# .github/workflows/powershell.yml
- name: Run PSScriptAnalyzer
  run: |
    Invoke-ScriptAnalyzer -Path .\ -Recurse -IncludeRule @(
        'PSAvoidGlobalAliases',
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
```

## 🔧 Development & Maintenance

### Code Organization Principles

**Function Categories**:

- **Public Functions**: User-facing cmdlets in `/functions/`
- **Internal Helpers**: Private utilities in `/internal/functions/`
- **Shared Logic**: Common patterns extracted to reusable helpers

**Naming Conventions**:

- **Functions**: `Verb-GTNoun` (e.g., `Get-GTUser`, `Disable-GTUser`)
- **Parameters**: Standard PowerShell parameter names with aliases
- **Variables**: PascalCase for public, camelCase for private

### Version Management

**Semantic Versioning**:

- **Major**: Breaking changes
- **Minor**: New features
- **Patch**: Bug fixes and improvements

**Changelog Structure**:

```markdown
## [0.20.0] - 2026-09-21

### Added
- Zero-dependency native REST engine replacing external Microsoft.Graph SDK

### Changed
- Standardized error handling and token lifecycle

### Fixed
- Throttling retry and nextLink pagination edge cases
```

## 🚀 Performance Characteristics

### API Call Optimization

**Request Batching**:

- **Bulk Operations**: Multiple items processed in single API calls where possible
- **Parallel Processing**: Independent operations executed concurrently
- **Caching**: Repeated data cached to reduce API calls

**Memory Management**:

- **Streaming Processing**: Large datasets processed without full memory load
- **Garbage Collection**: Automatic cleanup of temporary objects
- **Result Limiting**: Optional result size controls

### Scalability Considerations

**Large Tenant Support**:

- **Pagination Handling**: Automatic processing of large result sets
- **Timeout Management**: Configurable operation timeouts
- **Rate Limiting**: Respect for Microsoft Graph API limits

**Resource Efficiency**:

- **Connection Pooling**: Reuse of authenticated sessions
- **Lazy Loading**: Data retrieved only when needed
- **Selective Properties**: Only required attributes requested

## 🔗 Integration Capabilities

### PowerShell Ecosystem

**Module Compatibility**:

- **Zero-Dependency Architecture**: No external `Microsoft.Graph.*` SDK modules required; operates via native REST engine
- **PSFramework**: Logging and messaging infrastructure
- **Pester 5**: Comprehensive test automation suite (300+ integration and unit tests)

**Pipeline Integration**:

- **Standard Input/Output**: Compatible with PowerShell pipeline
- **Object Serialization**: Structured data for further processing
- **Error Stream**: Separate error handling channel

### Enterprise Integration

**SIEM Integration**:

- **Structured Logging**: PSFramework integration for centralized logging
- **Alert Generation**: Risk-based alerting capabilities
- **Audit Trail**: Comprehensive operation logging

**Automation Platforms**:

- **Azure Automation**: Runbook compatibility
- **GitHub Actions**: CI/CD pipeline integration
- **Scheduled Tasks**: Unattended execution support

## 📚 Documentation Architecture

### Multi-Layer Documentation

**README.md**: User-facing overview and quick start guide
**CHANGELOG.md**: Version history and release notes
**Function Help**: Comment-based help for detailed usage
**Specialized Docs**: Domain-specific deep dives

### Help System Integration

**Comment-Based Help**:

```powershell
<#
.SYNOPSIS
    Brief description of function purpose

.DESCRIPTION
    Detailed explanation with examples and parameter descriptions

.PARAMETER ParameterName
    Parameter description with type and validation info

.EXAMPLE
    Example usage with expected output
#>
```

**Localization Support**:

- **en-us Folder**: Culture-specific help files
- **String Resources**: Localized messages and error text

This technical documentation provides a comprehensive overview of GraphTools' architecture, implementation details, and advanced capabilities designed for enterprise security operations.
