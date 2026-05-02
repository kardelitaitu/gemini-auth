# PowerShell script to replace gemini references with gemini (case-sensitive)
# Run from the gemini-auth root directory

$ErrorActionPreference = "Stop"

Write-Host "Starting case-sensitive replacement..." -ForegroundColor Cyan

# Define replacements (case-sensitive)
$replacements = @(
    # Environment variables (uppercase)
    @{ Old = "GEMINI_HOME"; New = "GEMINI_HOME" },
    @{ Old = "GEMINI_HOME_DIR"; New = "GEMINI_HOME_DIR" },

    # Binary/package names (lowercase)
    @{ Old = "gemini-auth"; New = "gemini-auth" },
    @{ Old = "gemini_auth"; New = "gemini_auth" },

    # CLI commands (lowercase)
    @{ Old = "gemini"; New = "gemini" },

    # Uppercase first letter
    @{ Old = "Gemini"; New = "Gemini" },

    # Service/binary names (mixed case)
    @{ Old = "GeminiAuth"; New = "GeminiAuth" },
    @{ Old = "geminiauth"; New = "geminiAuth" }
)

# Get all files (excluding .git)
$files = Get-ChildItem -Path . -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' }

$totalReplacements = 0

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { continue }

    $originalContent = $content
    $fileReplacements = 0

    foreach ($r in $replacements) {
        # Use case-sensitive replace (no -i flag)
        $count = 0
        $content = $content -creplace [regex]::Escape($r.Old), $r.New
        # Count occurrences
        $count = ([regex]::Matches($originalContent, [regex]::Escape($r.Old))).Count
        $fileReplacements += $count
    }

    if ($content -ne $originalContent) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Updated: $($file.FullName.Replace($PWD, '.')) ($fileReplacements replacements)" -ForegroundColor Green
        $totalReplacements += $fileReplacements
    }
}

Write-Host "`nTotal replacements: $totalReplacements" -ForegroundColor Yellow
Write-Host "Done!" -ForegroundColor Cyan
