Describe "Documentation Integrity" -Tag 'Unit' {
    It "has no broken relative links across markdown files" {
        $repoRoot = Resolve-Path "$PSScriptRoot/.."
        $mdFiles = Get-ChildItem -Path $repoRoot -Recurse -Filter *.md | Where-Object {
            $_.FullName -notmatch '[\\/](\.git|\.gemini|scratch)[\\/]'
        }

        $brokenLinks = [System.Collections.Generic.List[string]]::new()

        foreach ($file in $mdFiles) {
            $content = Get-Content $file.FullName -Raw
            $matches = [regex]::Matches($content, '\[([^\]]+)\]\(([^)]+)\)')
            foreach ($match in $matches) {
                $link = $match.Groups[2].Value.Trim()
                # Skip external web URLs, anchors, mailto links, and absolute file URLs
                if ($link -notmatch '^https?://' -and $link -notmatch '^#' -and $link -notmatch '^mailto:' -and $link -notmatch '^file://') {
                    $cleanLink = ($link -split '#')[0]
                    if ($cleanLink) {
                        $targetPath = Join-Path $file.DirectoryName $cleanLink
                        if (-not (Test-Path $targetPath)) {
                            $brokenLinks.Add("File: $($file.Name) -> Link: $link")
                        }
                    }
                }
            }
        }

        $failureDetails = if ($brokenLinks.Count -gt 0) { "Found broken relative link(s):`n" + ($brokenLinks -join "`n") } else { '' }
        $brokenLinks.Count | Should -Be 0 -Because $failureDetails
    }
}
