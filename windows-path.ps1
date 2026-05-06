# PowerShell script to add gemini-auth to Windows PATH
# This allows running gemini-auth from any command prompt without npm installation

param(
    [switch]$Permanent,
    [switch]$Help
)

function Show-Help {
    Write-Host "windows-path.ps1 - Add gemini-auth to Windows PATH"
    Write-Host ""
    Write-Host "Usage: .\windows-path.ps1 [-Permanent] [-Help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Permanent    Add to system PATH permanently (requires admin)"
    Write-Host "  -Help         Show this help message"
    Write-Host ""
    Write-Host "Without -Permanent, adds to current session PATH only."
    Write-Host "Run 'zig build' first to ensure the executable is built."
}

if ($Help) {
    Show-Help
    exit 0
}

# Get the project directory
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $ProjectDir "zig-out\bin"

# Check if the executable exists
$ExePath = Join-Path $BinDir "gemini-auth.exe"
if (!(Test-Path $ExePath)) {
    Write-Host "Building gemini-auth executable..."
    try {
        & zig build
    } catch {
        Write-Error "Failed to build gemini-auth. Make sure Zig is installed."
        exit 1
    }
}

if (!(Test-Path $ExePath)) {
    Write-Error "gemini-auth.exe not found in $BinDir. Build may have failed."
    exit 1
}

Write-Host "Found gemini-auth.exe at: $ExePath"

if ($Permanent) {
    # Add to system PATH permanently (requires admin)
    Write-Host "Adding to system PATH permanently (requires administrator privileges)..."

    try {
        $CurrentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($CurrentPath -notlike "*$BinDir*") {
            $NewPath = "$CurrentPath;$BinDir"
            [Environment]::SetEnvironmentVariable("PATH", $NewPath, "Machine")
            Write-Host "Successfully added $BinDir to system PATH."
            Write-Host "Restart command prompts to use the new PATH."
        } else {
            Write-Host "$BinDir is already in system PATH."
        }
    } catch {
        Write-Error "Failed to modify system PATH. Run as administrator."
        exit 1
    }
} else {
    # Add to current session PATH
    Write-Host "Adding to current session PATH..."

    $CurrentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($CurrentPath -notlike "*$BinDir*") {
        $NewPath = "$CurrentPath;$BinDir"
        [Environment]::SetEnvironmentVariable("PATH", $NewPath, "User")
        # Also set for current process
        $env:PATH = "$env:PATH;$BinDir"
        Write-Host "Successfully added $BinDir to user PATH."
        Write-Host "Restart command prompts to use the new PATH."
    } else {
        Write-Host "$BinDir is already in user PATH."
    }

    # Test it
    Write-Host "Testing gemini-auth..."
    try {
        & gemini-auth --version
    } catch {
        Write-Host "gemini-auth is now available. Run 'gemini-auth --help' to see commands."
    }
}

Write-Host ""
Write-Host "To use gemini-auth from any command prompt, either:"
Write-Host "1. Run this script with -Permanent (as admin) for system-wide access"
Write-Host "2. Run this script without -Permanent for current user access"
Write-Host "3. Manually add '$BinDir' to your PATH environment variable"