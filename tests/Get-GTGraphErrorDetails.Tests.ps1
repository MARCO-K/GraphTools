## Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

# Pester tests for Get-GTGraphErrorDetails
# Requires Pester 5.x

Describe "Get-GTGraphErrorDetails" -Tag 'Unit' {
    BeforeAll {
        
        if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
        if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
        if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
        if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

        
        $functionFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'Get-GTGraphErrorDetails.ps1'
        if (-not (Test-Path $functionFile))
        {
            Throw "Function file not found: $functionFile"
        }
        . $functionFile
    }

    Context "HTTP Status Code Extraction" {
        It "extracts status code from Exception.Response.StatusCode" {
            # Create a mock exception with Response.StatusCode property
            $mockResponse = [PSCustomObject]@{ StatusCode = 404 }
            $exception = [System.Exception]::new('Not Found')
            $exception | Add-Member -NotePropertyName 'Response' -NotePropertyValue $mockResponse -Force

            $result = Get-GTGraphErrorDetails -Exception $exception

            $result.HttpStatus | Should -Be 404
            $result.Reason | Should -Match 'could not be processed'
            $result.LogLevel | Should -Be 'Error'
        }

        It "extracts status code from Exception.InnerException.Response.StatusCode" {
            # Create a mock inner exception with Response.StatusCode property
            $mockResponse = [PSCustomObject]@{ StatusCode = 403 }
            $innerException = [System.Exception]::new('Forbidden')
            $innerException | Add-Member -NotePropertyName 'Response' -NotePropertyValue $mockResponse -Force

            $exception = [System.Exception]::new('Outer exception', $innerException)

            $result = Get-GTGraphErrorDetails -Exception $exception

            $result.HttpStatus | Should -Be 403
            $result.Reason | Should -Match 'could not be processed'
            $result.LogLevel | Should -Be 'Error'
        }

        It "extracts 404 status from error message pattern" {
            $exception = [System.Exception]::new('404 Not Found - The resource does not exist')

            $result = Get-GTGraphErrorDetails -Exception $exception

            $result.HttpStatus | Should -Be 404
            $result.Reason | Should -Match 'could not be processed'
        }

        It "extracts 403 status from 'Insufficient privileges' message" {
            $exception = [System.Exception]::new('Insufficient privileges to complete the operation')

            $result = Get-GTGraphErrorDetails -Exception $exception

            $result.HttpStatus | Should -Be 403
            $result.Reason | Should -Match 'could not be processed'
        }

        It "extracts 429 status from 'throttl' message" {
            $exception = [System.Exception]::new('Request was throttled due to rate limiting')

            $result = Get-GTGraphErrorDetails -Exception $exception

            $result.HttpStatus | Should -Be 429
            $result.Reason | Should -Match 'Throttled'
            $result.LogLevel | Should -Be 'Warning'
        }

        It "extracts 400 status from 'Bad Request' message" {
            $exception = [System.Exception]::new('400 Bad Request - Invalid input')

            $result = Get-GTGraphErrorDetails -Exception $exception

            $result.HttpStatus | Should -Be 400
            $result.Reason | Should -Match 'Bad request'
        }
    }

    Context "Error Message Composition" {
        It "returns generic message for 404 to prevent enumeration" {
            $exception = [System.Exception]::new('404 Not Found')

            $result = Get-GTGraphErrorDetails -Exception $exception -ResourceType 'user'

            $result.Reason | Should -Be 'Operation failed. The user could not be processed.'
            $result.Reason | Should -Not -Match '404'
        }

        It "returns generic message for 403 to prevent enumeration" {
            $exception = [System.Exception]::new('403 Forbidden')

            $result = Get-GTGraphErrorDetails -Exception $exception -ResourceType 'device'

            $result.Reason | Should -Be 'Operation failed. The device could not be processed.'
            $result.Reason | Should -Not -Match '403'
        }

        It "returns detailed message for 429 throttling" {
            $exception = [System.Exception]::new('429 Too Many Requests')

            $result = Get-GTGraphErrorDetails -Exception $exception

            $result.Reason | Should -Match 'Throttled by Graph API'
            $result.Reason | Should -Match 'exponential backoff'
        }

        It "includes original error message for 400 errors" {
            $exception = [System.Exception]::new('400 Bad Request - Invalid parameter')

            $result = Get-GTGraphErrorDetails -Exception $exception

            $result.Reason | Should -Match 'Bad request'
            $result.Reason | Should -Match 'Invalid parameter'
        }

        It "returns full error message for unknown status codes" {
            $exception = [System.Exception]::new('Some unexpected error occurred')

            $result = Get-GTGraphErrorDetails -Exception $exception

            $result.HttpStatus | Should -BeNullOrEmpty
            $result.Reason | Should -Match 'Failed: Some unexpected error occurred'
        }
    }

    Context "ResourceType Parameter" {
        It "uses 'user' in error message when ResourceType is 'user'" {
            $exception = [System.Exception]::new('404 Not Found')

            $result = Get-GTGraphErrorDetails -Exception $exception -ResourceType 'user'

            $result.Reason | Should -Match 'user could not be processed'
        }

        It "uses 'device' in error message when ResourceType is 'device'" {
            $exception = [System.Exception]::new('404 Not Found')

            $result = Get-GTGraphErrorDetails -Exception $exception -ResourceType 'device'

            $result.Reason | Should -Match 'device could not be processed'
        }

        It "uses 'resource' by default when ResourceType is not specified" {
            $exception = [System.Exception]::new('404 Not Found')

            $result = Get-GTGraphErrorDetails -Exception $exception

            $result.Reason | Should -Match 'resource could not be processed'
        }
    }

    Context "Output Structure" {
        It "returns object with all expected properties" {
            $exception = [System.Exception]::new('Test error')

            $result = Get-GTGraphErrorDetails -Exception $exception

            $result.PSObject.Properties.Name | Should -Contain 'HttpStatus'
            $result.PSObject.Properties.Name | Should -Contain 'Reason'
            $result.PSObject.Properties.Name | Should -Contain 'ErrorMessage'
            $result.PSObject.Properties.Name | Should -Contain 'LogLevel'
        }

        It "preserves original error message in ErrorMessage property" {
            $errorText = 'Original error message with details'
            $exception = [System.Exception]::new($errorText)

            $result = Get-GTGraphErrorDetails -Exception $exception

            $result.ErrorMessage | Should -Be $errorText
        }

        It "sets appropriate LogLevel for different status codes" {
            $ex404 = [System.Exception]::new('404 Not Found')
            $ex429 = [System.Exception]::new('429 throttled')

            $result404 = Get-GTGraphErrorDetails -Exception $ex404
            $result429 = Get-GTGraphErrorDetails -Exception $ex429

            $result404.LogLevel | Should -Be 'Error'
            $result429.LogLevel | Should -Be 'Warning'
        }
    }
}
