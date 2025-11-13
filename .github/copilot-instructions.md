# GraphTools - Copilot Coding Agent Instructions

## Repository Overview

**GraphTools** is a PowerShell module providing Microsoft Entra ID (Azure AD) security management, incident response, and reporting capabilities via Microsoft Graph API. The module is designed for IT security professionals to manage user accounts, security incidents, MFA status, licensing, and audit logs.

- **Repository Size**: ~936KB with 64 files
- **Primary Language**: PowerShell (50 .ps1 files)
- **Module Type**: PowerShell Script Module (.psm1 with .psd1 manifest)
- **Target Platforms**: PowerShell 5.1+ and PowerShell 7+
- **Main Dependencies**: PSFramework (≥1.9.270), Microsoft.Graph.Beta.Reports (≥2.25.0), Microsoft Graph SDK modules

## Project Structure

```
GraphTools/
├── GraphTools.psd1          # Module manifest (version, dependencies, metadata)
├── GraphTools.psm1          # Module loader (dot-sources all functions)
├── functions/               # 14 public cmdlets (exported to users)
├── internal/
│   └── functions/          # 22 internal helper functions (not exported)
├── tests/                   # 14 Pester test files (.Tests.ps1)
├── docs/                    # User-Security-Response.md guide
├── en-us/                   # Help text and localization strings
├── .github/
│   └── workflows/
│       └── powershell.yml  # PSScriptAnalyzer CI workflow
├── README.md               # Comprehensive documentation
└── CHANGELOG.md            # Version history

```

### Key Files by Purpose

- **Module Entry Point**: `GraphTools.psd1` (manifest) → `GraphTools.psm1` (loader)
- **Validation**: `internal/functions/GTValidation.ps1` - UPN regex validation
- **Graph Connection**: `internal/functions/Initialize-GTGraphConnection.ps1` - Connection management
- **Module Installation**: `internal/functions/Install-GTRequiredModule.ps1` - Dependency handling
- **Public Functions**: All `.ps1` files in `functions/` directory are exported cmdlets
- **Internal Helpers**: All `.ps1` files in `internal/functions/` are private functions

### Function Categories

**Security Incident Response** (5 cmdlets):
- `Revoke-GTSignOutFromAllSessions` - Invalidate refresh tokens
- `Disable-GTUser` - Block account sign-ins
- `Reset-GTUserPassword` - Force password reset
- `Disable-GTUserDevice` - Disable registered devices  
- `Remove-GTUserEntitlements` - Remove all access rights

**Reporting & Analytics** (9 cmdlets):
- `Get-MFAReport` - MFA status and methods
- `Get-M365LicenceOverview` - License utilization
- `Invoke-AuditLogQuery` - Audit log queries
- `Get-GTInactiveUsers` - Dormant accounts
- `Get-GTRecentUser` - Recently created accounts
- `Get-GTConditionalAccessPolicyReport` - CA policy analysis
- `Get-GTPolicyControlGapReport` - Policy gaps
- `Get-GTServicePrincipalReport` - Service principals
- `Get-GTOrphanedGroup` - Orphaned groups

## Build, Test, and Validation

### Prerequisites

**CRITICAL**: This environment does NOT have internet access to PSGallery. The module requires:
- PSFramework (≥1.9.270)
- Microsoft.Graph.Beta.Reports (≥2.25.0)
- Various Microsoft.Graph.* modules (loaded on-demand by functions)

These dependencies are declared in `GraphTools.psd1` but cannot be installed in this sandboxed environment. Functions will fail at runtime if dependencies are missing.

### Module Loading

**DO NOT attempt to import the module** in this environment. Running `Import-Module ./GraphTools.psd1` will fail because required modules are not available and PSGallery is not accessible.

### Linting with PSScriptAnalyzer

The CI workflow (`.github/workflows/powershell.yml`) runs PSScriptAnalyzer on all PowerShell files. It enforces these rules:
- `PSAvoidGlobalAliases` - No global aliases
- `PSAvoidUsingConvertToSecureStringWithPlainText` - No plain text secure strings

**To validate locally** (if PSScriptAnalyzer is available):
```powershell
Invoke-ScriptAnalyzer -Path .\ -Recurse -IncludeRule 'PSAvoidGlobalAliases', 'PSAvoidUsingConvertToSecureStringWithPlainText'
```

**CI Workflow Trigger**: Runs on push/PR to `main` branch and weekly schedule (Friday 15:30 UTC)

### Testing with Pester

Tests are located in `tests/` directory with naming pattern `<FunctionName>.Tests.ps1`. The repository uses **Pester 5.x** (5.7.1+ available).

**Test Structure**:
- Each test file sources the function: `. "$PSScriptRoot/../functions/<FunctionName>.ps1"`
- Uses `BeforeAll`, `BeforeEach`, and `Describe` blocks
- Mocks Microsoft Graph cmdlets to avoid live API calls
- Tests parameter validation, pipeline input, and error conditions

**To run tests** (if Pester is available):
```powershell
# Run all tests
Invoke-Pester -Path ./tests/

# Run specific test
Invoke-Pester -Path ./tests/Disable-GTUser.Tests.ps1

# Run with detailed output
Invoke-Pester -Path ./tests/ -Output Detailed
```

**Note**: Tests cannot run in this environment without mock dependencies.

### No Build Step Required

This is a pure PowerShell script module. There is **no compilation, build, or packaging step**. Changes to `.ps1` files are immediately effective when the module is re-imported.

## Development Guidelines

### PowerShell Cmdlet Standards

All functions MUST follow these conventions:

1. **Naming**: Use approved PowerShell verbs (`Get-Verb`) with Verb-Noun format and `GT` prefix (e.g., `Get-GTUser`, `Disable-GTUser`)

2. **Comment-Based Help**: Every public function requires complete help with:
   - `.SYNOPSIS` - Brief description
   - `.DESCRIPTION` - Detailed explanation
   - `.PARAMETER` - Each parameter documented with aliases listed
   - `.EXAMPLE` - Multiple usage examples showing different parameter sets

3. **Parameter Design**:
   - Use `[CmdletBinding()]` on all functions
   - Support pipeline input with `ValueFromPipeline = $true`
   - Use parameter aliases for flexibility (see below)
   - Validate UPNs with `[ValidateScript({$_ -match $script:GTValidationRegex.UPN})]`
   - Use `[switch]` for boolean flags (not `[bool]`)

4. **User Parameter Aliases**: For user identification, ALWAYS include these aliases:
   ```powershell
   [Alias('UPN','UserPrincipalName','Users','User','UserName','UPNName')]
   [string[]]$UPN
   ```

5. **Function Structure** (use Begin/Process/End):
   ```powershell
   begin {
       # Module installation
       Install-GTRequiredModule -ModuleNames @('Module1', 'Module2')
       
       # Graph connection
       $connected = Initialize-GTGraphConnection -Scopes 'Required.Scope'
       if (-not $connected) { throw "Failed to connect" }
   }
   process {
       foreach ($item in $InputParameter) {
           # Process each item
       }
   }
   end {
       # Cleanup if needed
   }
   ```

6. **Error Handling**: Use `try/catch` blocks with PSFramework logging:
   ```powershell
   try {
       # Operation
       Write-PSFMessage -Level Verbose -Message "Success message"
   }
   catch {
       Write-PSFMessage -Level Error -Message "Error: $($_.Exception.Message)"
   }
   ```

7. **Output**: Return objects (not formatted text). Use `[PSCustomObject]` for structured output.

### Code Patterns to Follow

**UPN Validation**: All user parameters must validate against the regex defined in `internal/functions/GTValidation.ps1`:
```powershell
$script:GTValidationRegex = @{
    UPN = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
}
```

**Module Dependencies**: Functions handle their own module installation:
```powershell
$modules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Users')
Install-GTRequiredModule -ModuleNames $modules -Verbose
```

**Graph Connection**: Always initialize Graph connection with required scopes:
```powershell
$connectionResult = Initialize-GTGraphConnection -Scopes 'User.ReadWrite.All'
if (-not $connectionResult) {
    Write-PSFMessage -Level Error -Message "Failed to connect"
    return
}
```

**Pipeline Support**: Accumulate pipeline input in `process` block, process in `end` block for batch operations:
```powershell
begin {
    $UPNList = [System.Collections.Generic.List[string]]::new()
}
process {
    if ($UserPrincipalName) {
        foreach($upn in $UserPrincipalName) {
            $UPNList.Add($upn)
        }
    }
}
end {
    # Process accumulated $UPNList
}
```

### Testing Patterns

When creating tests for new functions:

1. **Source the function**: `. "$PSScriptRoot/../functions/YourFunction.ps1"`
2. **Mock Microsoft Graph cmdlets**: All `*-MgBeta*` cmdlets must be mocked
3. **Test parameter validation**: Ensure invalid UPNs throw errors
4. **Test pipeline input**: Verify single and multiple values from pipeline
5. **Test switch parameters**: Verify filtering and behavior changes
6. **Test error conditions**: Verify proper error handling

Example test structure:
```powershell
. "$PSScriptRoot/../functions/YourFunction.ps1"

Describe "YourFunction" {
    BeforeAll {
        Mock Install-GTRequiredModule { }
        Mock Initialize-GTGraphConnection { $true }
    }
    
    Context "Parameter Validation" {
        It "should throw for invalid UPN" {
            { YourFunction -UPN "invalid" } | Should -Throw
        }
    }
    
    Context "Pipeline Input" {
        It "should accept single UPN from pipeline" {
            $result = 'user@contoso.com' | YourFunction
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
```

## Common Pitfalls and Workarounds

### Environment Limitations

1. **No PSGallery Access**: Cannot install modules. Do not attempt `Install-Module` commands.
2. **No Live Graph API**: Cannot test actual Graph API calls. Rely on existing tests.
3. **Module Dependencies**: The module cannot be imported without PSFramework and Microsoft Graph modules.

### Development Approach

**When making code changes**:
1. Edit `.ps1` files directly - no build step needed
2. Review syntax and structure manually (PSScriptAnalyzer not available)
3. Follow existing patterns from other functions
4. Add tests following existing test patterns
5. Update function help if parameters change
6. Do NOT try to run the module or tests (dependencies unavailable)

**Parameter changes**:
- If adding user-related parameters, include standard aliases
- Update comment-based help with `.PARAMETER` documentation
- Add validation attributes as needed
- Consider backward compatibility

**Adding new functions**:
1. Create `functions/YourFunction.ps1` with full comment-based help
2. Follow Begin/Process/End pattern
3. Add module installation in `begin` block
4. Add Graph connection initialization
5. Create `tests/YourFunction.Tests.ps1` with mocks
6. Function will auto-export (FunctionsToExport = '*' in manifest)

## File Locations Quick Reference

- **Module Manifest**: `/GraphTools.psd1` - version, author, dependencies
- **Module Loader**: `/GraphTools.psm1` - imports all functions
- **Public Functions**: `/functions/*.ps1` - exported cmdlets (14 files)
- **Internal Functions**: `/internal/functions/*.ps1` - helpers (22 files)
- **Tests**: `/tests/*.Tests.ps1` - Pester tests (14 files)
- **Documentation**: `/README.md`, `/docs/User-Security-Response.md`, `/CHANGELOG.md`
- **CI Workflow**: `/.github/workflows/powershell.yml` - PSScriptAnalyzer
- **Help Files**: `/en-us/about_GraphTools.help.txt`, `/en-us/strings.psd1`

## Validation Checklist

Before submitting changes, ensure:

- [ ] All functions follow Verb-Noun naming with `GT` prefix
- [ ] Comment-based help is complete (SYNOPSIS, DESCRIPTION, PARAMETER, EXAMPLE)
- [ ] User parameters include standard aliases (`UPN`, `UserPrincipalName`, etc.)
- [ ] UPN validation uses `$script:GTValidationRegex.UPN`
- [ ] Functions use Begin/Process/End pattern
- [ ] Module dependencies are installed in `begin` block
- [ ] Graph connection is initialized with required scopes
- [ ] Error handling uses `try/catch` with PSFramework logging
- [ ] Test file exists with proper mocking
- [ ] Code follows PowerShell best practices (no global aliases, etc.)

## Trust These Instructions

These instructions are comprehensive and validated against the actual repository structure. **Only perform additional exploration if**:
- Information here is incomplete or unclear
- You encounter unexpected errors suggesting these instructions are incorrect
- You're implementing a feature type not covered by existing patterns

For standard function modifications, testing, or additions, follow the patterns documented here without additional searching.
