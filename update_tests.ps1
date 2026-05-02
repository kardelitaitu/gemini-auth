# PowerShell script to update remaining test files for Gemini migration
# Replaces OpenAI-specific patterns with Gemini equivalents

$ErrorActionPreference = "Stop"

Write-Host "Updating test files for Gemini migration..." -ForegroundColor Cyan

# Define replacements
$replacements = @(
    # Remove OpenAI-specific patterns
    @{ Pattern = "chatgpt_account_id"; Replacement = "google_user_id"; CaseSensitive = $true },
    @{ Pattern = "chatgpt_user_id"; Replacement = "google_user_id"; CaseSensitive = $true },
    @{ Pattern = "auth_mode"; Replacement = "plan"; CaseSensitive = $true },  # Simplified - use plan instead
    @{ Pattern = '"plan_type": "prolite"'; Replacement = '"plan_type": "pro"'; CaseSensitive = $true },
    @{ Pattern = '"plan_type": "plus"'; Replacement = '"plan_type": "pro"'; CaseSensitive = $true },
    @{ Pattern = '"plan_type": "team"'; Replacement = '"plan_type": "ultra"'; CaseSensitive = $true },
    @{ Pattern = '"plan_type": "business"'; Replacement = '"plan_type": "ultra"'; CaseSensitive = $true },
    @{ Pattern = '"plan_type": "enterprise"'; Replacement = '"plan_type": "ultra"'; CaseSensitive = $true },
    @{ Pattern = "https://api.openai.com/auth"; Replacement = "https://www.googleapis.com/auth"; CaseSensitive = $true },
    @{ Pattern = "user-ESYgcy2QkOGZc0NoxSlFCeVT"; Replacement = "google_user_123"; CaseSensitive = $true },
    @{ Pattern = "67fe2bbb-0de6-49a4-b2b3-d1df366d1faf"; Replacement = "account_123"; CaseSensitive = $true },
    @{ Pattern = '"access_token": "access-'; Replacement = '"access_token": "ya29.a0.test_'; CaseSensitive = $true },
    @{ Pattern = "auth.json"; Replacement = "oauth_creds.json"; CaseSensitive = $true },
    @{ Pattern = "accountNameRefreshLock"; Replacement = "accountLock"; CaseSensitive = $true },
    @{ Pattern = "account_name_refresh_lock_file_name"; Replacement = "account_lock_file_name"; CaseSensitive = $true }
)

# Get all test files
$testFiles = Get-ChildItem -Path "C:\My Script\gemini-auth\tests" -Filter "*.zig" -Recurse | Where-Object { $_.FullName -notmatch "fixtures" }

$totalReplacements = 0

foreach ($file in $testFiles) {
    $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { continue }
    
    $originalContent = $content
    $fileReplacements = 0
    
    foreach ($r in $replacements) {
        $count = 0
        if ($r.CaseSensitive) {
            $content = $content -creplace [regex]::Escape($r.Pattern), $r.Replacement
            $count = ([regex]::Matches($originalContent, [regex]::Escape($r.Pattern))).Count
        }
        $fileReplacements += $count
    }
    
    if ($content -ne $originalContent) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Updated: $($file.FullName.Replace($PWD.Path, '.')) ($fileReplacements replacements)" -ForegroundColor Green
        $totalReplacements += $fileReplacements
    }
}

Write-Host "`nTotal replacements: $totalReplacements" -ForegroundColor Yellow
Write-Host "Done!" -ForegroundColor Cyan
