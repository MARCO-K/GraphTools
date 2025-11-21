# GraphTools Technical Highlights

## 🏗️ Technical Architecture

### Module Structure

GraphTools is built as a PowerShell script module with a clean, modular architecture designed for enterprise security operations:

```
GraphTools/
├── GraphTools.psd1          # Module manifest with dependency management
├── GraphTools.psm1          # Module loader with automatic function discovery
├── functions/               # Public cmdlets (15 functions)
├── internal/
│   └── functions/          # Private helpers (22 functions)
├── tests/                   # Pester test suite (15 test files)
├── docs/                    # Comprehensive documentation
└── en-us/                   # Localization and help files
```

### PowerShell Standards Compliance

- **PowerShell Version Support**: 5.1+ and 7.0+
- **Cmdlet Naming**: Approved verbs with `GT` prefix (`Get-GTUser`, `Disable-GTUser`)
- **Parameter Binding**: Full `[CmdletBinding()]` support with pipeline input
- **Comment-Based Help**: Complete help documentation for all public functions
- **Error Handling**: Structured error responses with HTTP status codes

## 🔧 Core Technical Features

### Microsoft Graph API Integration

**Multi-Endpoint Support**:

- **Stable API**: Production-ready endpoints (`v1.0`)
- **Beta API**: Preview features (`beta`) for advanced capabilities
- **Automatic Fallback**: Graceful degradation when beta features unavailable

**Authentication & Authorization**:

- **Delegated Permissions**: Interactive user authentication
- **Application Permissions**: Unattended service operations
- **Scope Management**: Automatic scope validation and connection handling
- **Session Management**: `NewSession` parameter for connection refresh

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
    # Module installation and connection setup
    Install-GTRequiredModule -ModuleNames $modules
    Initialize-GTGraphConnection -Scopes $requiredScopes
}
process {
    # Process each pipeline item
    foreach ($item in $InputParameter) { ... }
}
end {
    # Final processing and output
    return $results
}
```

**Memory-Efficient Processing**:

- **Streaming Input**: No requirement to load all data at once
- **Lazy Evaluation**: Results generated as needed
- **Resource Cleanup**: Automatic disposal of large datasets

### Module Auto-Management

**Dependency Resolution**:

```powershell
# Automatic module installation
$modules = @('Microsoft.Graph.Beta.Applications', 'Microsoft.Graph.Users')
Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference
```

**Connection Lifecycle**:

- **Automatic Connection**: Functions establish Graph connections as needed
- **Scope Validation**: Required permissions verified before operations
- **Session Reuse**: Connection pooling for multiple operations

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
        Mock Get-MgContext { @{ Scopes = @('AppRoleAssignment.Read.All') } }
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
## [0.17.0] - 2025-11-21

### Added
- New function with comprehensive description

### Changed
- Updated existing functionality

### Fixed
- Bug fixes and improvements
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

- **PSFramework**: Logging and messaging infrastructure
- **Microsoft Graph SDK**: Official PowerShell modules for Graph API
- **Pester**: Testing framework integration

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
