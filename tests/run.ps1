<#
    run.ps1 - Syntax-check the addon and run every tests\test_*.lua under Lua 5.1,
    through WowTestKit at the commit tests\kit.pin names (its scripts\run.ps1).

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -KitDev      # the ..\WowTestKit working copy, not the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$KitDev
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Lua)) { Write-Error "Lua 5.1 not found at $Lua (pass -Lua <path>)"; exit 1 }
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    # The tests load the LibGlass checkout as it is; CI loads the .pkgmeta pin.
    # Running against something else is fine (a library change before a pin
    # bump) but must not pass for a check of what ships.
    $libGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
    $pin = (Get-Content ".pkgmeta") | Where-Object { $_ -match '^\s+(commit|tag):\s*(\S+)\s*$' } |
        ForEach-Object { $Matches[2] } | Select-Object -First 1
    if ($pin -and (Test-Path -LiteralPath $libGlass)) {
        $want = git -C $libGlass rev-parse --verify --quiet "$pin^{commit}" 2>$null
        $head = git -C $libGlass rev-parse HEAD 2>$null
        $dirty = git -C $libGlass status --porcelain 2>$null
        if (-not $want -or $want -ne $head -or $dirty) {
            Write-Host "WARNING: LibGlass at $libGlass is not the .pkgmeta pin ($pin)$(if ($dirty) { ', or has uncommitted changes' }); CI tests the pin" -ForegroundColor Yellow
        } else {
            Write-Host "LibGlass: $libGlass at the pin ($pin)" -ForegroundColor DarkGray
        }
    } elseif (-not $pin) {
        Write-Host "WARNING: no LibGlass commit/tag pin readable in .pkgmeta (an inline comment on the value line?); CI's fetch will fail" -ForegroundColor Yellow
    }
    # The probe's files, syntax-checked with the TOC's (the TOC is the list, so
    # a new file cannot go unchecked). Only our own .lua: the embedded LibGlass
    # is checked in its repo.
    $probe = @(Get-ChildItem "Tools\RaidProbe\*.lua" | ForEach-Object { Resolve-Path -Relative $_.FullName })
}
finally { Pop-Location }

. (Join-Path $PSScriptRoot "kit.ps1")
$kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev
& (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "GlassRaidFrames.toc" -Extra $probe -Lua $Lua
exit $LASTEXITCODE
