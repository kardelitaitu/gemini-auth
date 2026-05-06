# PowerShell script to fix remaining Gemini migration issues
$ErrorActionPreference = "Stop"

Write-Host "Fixing remaining OpenAI references..." -ForegroundColor Cyan

# Fix 1: Replace '.plan = .chatgpt,' with valid Gemini plan types
# In Gemini, we don't have auth_mode field, and .chatgpt is not a valid PlanType
$planFixes = @{
    '.plan = .chatgpt,' = '.plan = .pro,'  # Default to pro
}

# Track changes
$totalChanges = 0

# Get all test files with remaining issues
$testFiles = Get-ChildItem -Path "C:\My Script\gemini-auth\tests" -Filter "*.zig" -Recurse | 
    Where-Object { $_.FullName -notmatch "fixtures" }

foreach ($file in $testFiles) {
    $content = Get-Content -Path $file.FullName -Raw
    if ($null -eq $content) { continue }
    
    $originalContent = $content
    $fileChanges = 0
    
    # Fix .plan = .chatgpt,
    if ($content -match '\.plan = \.chatgpt,') {
        $content = $content -replace '\.plan = \.chatgpt,' -replace '.plan = .pro,'
        $fileChanges += $matches.Count
    }
    
    # Fix duplicate .google_user_id lines (keep first, remove second)
    # Pattern: two consecutive lines with .google_user_id = ...
    $lines = $content -split "`n"
    $newLines = @()
    $prevLineGoogle = $false
    $dupCount = 0
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '\.\google_user_id = try allocator\.dupe\(u8, google_user_id\)') {
            if ($prevLineGoogle) {
                # Skip this duplicate line
                $dupCount++
                continue
            }
            $prevLineGoogle = $true
        } else {
            $prevLineGoogle = $false
        }
        $newLines += $line
    }
    
    if ($dupCount -gt 0) {
        $content = $newLines -join "`n"
        $content += "`n"  # Add trailing newline
        $fileChanges += $dupCount
    }
    
    # Fix .account_name = null, to .name = null, (Gemini uses 'name' not 'account_name')
    if ($content -match '\.\account_name = null,') {
        $content = $content -replace '\.\account_name = null,' -replace '    .name = null,'
        $fileChanges += $matches.Count
    }
    
    if ($content -ne $originalContent) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Fixed: $($file.FullName.Replace($PWD.Path, '.')) ($fileChanges changes)" -ForegroundColor Green
        $totalChanges += $fileChanges
    }
}

Write-Host "`nTotal changes: $totalChanges" -ForegroundColor Yellow
Write-Host "Done!" -ForegroundColor Cyan
