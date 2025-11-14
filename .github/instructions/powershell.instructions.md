---
applyTo: "**/*.ps1,**/*.psm1,**/*.psd1"

---
You are a professional Powershell scripter.

# PowerShell Cmdlet Development Guidelines

This guide provides PowerShell-specific instructions to help GitHub Copilot generate idiomatic, safe, and maintainable scripts. It aligns with Microsoft’s PowerShell cmdlet development guidelines.

## General rules

 - **Comment-Based Help:**
  - Include comment-based help for any public-facing function or cmdlet. 

- **Consistent Formatting:**
  - Follow consistent PowerShell style
  - Use proper indentation (4 spaces recommended)
  - Opening braces on same line as statement
  - Closing braces on new line
  - Use line breaks after pipeline operators
  - PascalCase for function and parameter names
  - Avoid unnecessary whitespace****

## Naming Conventions

- **Verb-Noun Format:**
  - Use approved PowerShell verbs (Get-Verb)
  - Use singular nouns
  - PascalCase for both verb and noun
  - Avoid special characters and spaces

- **Parameter Names:**
  - Use PascalCase
  - Choose clear, descriptive names
  - Use singular form unless always multiple
  - Follow PowerShell standard names

- **Variable Names:**
  - Use PascalCase for public variables
  - Use camelCase for private variables
  - Avoid abbreviations
  - Use meaningful names

- **Alias Avoidance:**
  - Use full cmdlet names
  - Avoid using aliases in scripts (e.g., use Get-ChildItem instead of gci)
  - Document any custom aliases
  - Use full parameter names

## Parameter Design

- **Standard Parameters:**
  - Use common parameter names (`Path`, `Name`, `Force`)
  - Follow built-in cmdlet conventions
  - Use aliases for specialized terms
  - Document parameter purpose

- **Parameter Names:**
  - Use singular form unless always multiple
  - Choose clear, descriptive names
  - Follow PowerShell conventions
  - Use PascalCase formatting

- **Type Selection:**
  - Use common .NET types
  - Implement proper validation
  - Consider ValidateSet for limited options
  - Enable tab completion where possible

- **Switch Parameters:**
  - Use [switch] for boolean flags
  - Avoid $true/$false parameters
  - Default to $false when omitted
  - Use clear action names

- **Collection Parameters (PowerShell 7+):**
  - When using `System.Collections.Generic.List[T]` parameters, add `[AllowEmptyCollection()]` attribute
  - PowerShell 7+ validates that collections are non-empty by default during parameter binding
  - Example: `[Parameter(Mandatory = $true)] [AllowEmptyCollection()] [System.Collections.Generic.List[PSObject]]$Results`
  - This is critical for functions that need to accept empty lists to populate them

## Pipeline and Output

- **Pipeline Input:**
  - Use `ValueFromPipeline` for direct object input
  - Use `ValueFromPipelineByPropertyName` for property mapping
  - Implement Begin/Process/End blocks for pipeline handling
  - Document pipeline input requirements

- **Output Objects:**
  - Return rich objects, not formatted text
  - Use PSCustomObject for structured data
  - Avoid Write-Host for data output
  - Enable downstream cmdlet processing

- **Pipeline Streaming:**
  - Output one object at a time
  - Use process block for streaming
  - Avoid collecting large arrays
  - Enable immediate processing

- **PassThru Pattern:**
  - Default to no output for action cmdlets
  - Implement `-PassThru` switch for object return
  - Return modified/created object with `-PassThru`
  - Use verbose/warning for status updates

## Error Handling and Safety

- **ShouldProcess Implementation:**
  - Use `[CmdletBinding(SupportsShouldProcess = $true)]`
  - Call `$PSCmdlet.ShouldProcess()` for system changes

- **Message Streams:**
  - Avoid `Write-Host` except for user interface text

- **Error Handling Pattern:**
  - Use try/catch blocks for error management
  - Set appropriate ErrorAction preferences
  - Return meaningful error messages
  - Use ErrorVariable when needed
  - Include proper terminating vs non-terminating error handling

- **Non-Interactive Design:**
  - Accept input via parameters
  - Avoid `Read-Host` in scripts
  - Support automation scenarios
  - Document all required inputs

## Testing with Pester

- **Test Structure:**
  - Use Pester 5.x syntax with `Describe`, `Context`, `It`, `BeforeAll`, `BeforeEach`
  - Place test files in `tests/` directory with `.Tests.ps1` suffix
  - Name test files to match the function being tested

- **Mocking Dependencies:**
  - Define stub functions in `BeforeAll` block before sourcing the function under test
  - Stub functions must exist before Mock can override them
  - Example:
    ```powershell
    BeforeAll {
        function Get-MgBetaUser { }  # Stub
        . "$PSScriptRoot/../functions/MyFunction.ps1"  # Source after stubs
        Mock -CommandName "Get-MgBetaUser" -MockWith { ... }  # Mock the stub
    }
    ```
  - For internal functions, also stub Write-PSFMessage and any Microsoft Graph cmdlets used

- **Testing Internal Functions:**
  - Internal functions (in `internal/functions/`) use `[AllowEmptyCollection()]` for List parameters
  - Create new List instances in each test: `$results = [System.Collections.Generic.List[PSObject]]::new()`
  - Don't reuse Lists between tests to avoid parameter binding issues

- **Validation Testing:**
  - Test parameter validation separately in a dedicated context
  - Use ValidateScript attribute with regex from GTValidation.ps1 for UPN parameters
  - Test both valid and invalid inputs

