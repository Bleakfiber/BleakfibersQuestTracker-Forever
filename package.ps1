<#
    Automated Packaging Script for Bleakfiber Addons
    Usage:
        .\package.ps1
        .\package.ps1 -Version "1.0.18" -Notes "Feature update description"
#>

param (
    [string]$Version,
    [string]$Notes
)

$ErrorActionPreference = "Stop"
$rootDir = $PSScriptRoot

# Locate the nested addon distribution subfolder
$addonDirs = Get-ChildItem -Directory -Path $rootDir | Where-Object { 
    Test-Path (Join-Path $_.FullName "$($_.Name).toc") 
}

if (-not $addonDirs) {
    Write-Error "Could not find a valid addon subfolder with a matching .toc file."
    exit 1
}

$addonDir = $addonDirs[0].FullName
$addonName = $addonDirs[0].Name
$tocFile = Join-Path $addonDir "$addonName.toc"
$changelogFile = Join-Path $addonDir "CHANGELOG.md"
if (-not (Test-Path $changelogFile)) {
    $changelogFile = Join-Path $rootDir "CHANGELOG.md"
}

# Version Update
if ($Version) {
    Write-Host "Updating version to $Version..." -ForegroundColor Cyan
    (Get-Content $tocFile) -replace '^## Version: .*$', "## Version: $Version" | Set-Content $tocFile
} else {
    $tocContent = Get-Content $tocFile -Raw
    if ($tocContent -match '## Version:\s*([^\r\n]+)') {
        $Version = $matches[1].Trim()
    } else {
        $Version = "1.0.18"
    }
}

Write-Host "Packaging $addonName v$Version..." -ForegroundColor Green

# Changelog Entry
if (Test-Path $changelogFile) {
    $changelog = Get-Content $changelogFile -Raw
    if ($changelog -notmatch "\[$Version\]") {
        $dateStr = (Get-Date).ToString("yyyy-MM-dd")
        $noteBody = if ($Notes) { "- $Notes" } else { "- Native Dark Slate & Gold configuration GUI, dynamic element reflow, and auto-hiding scrollbar." }
        $entry = @"

## [$Version] - $dateStr

### Changed
$noteBody

"@
        if ($changelog -match "(# Changelog[\s\S]*?\n\n)") {
            $header = $matches[1]
            $changelog = $changelog.Replace($header, $header + $entry.TrimStart() + "`n")
        } else {
            $changelog = $entry + "`n" + $changelog
        }
        Set-Content -Path $changelogFile -Value $changelog -NoNewline
        Write-Host "Recorded [$Version] in CHANGELOG.md" -ForegroundColor Yellow
    }
}

# Ensure \zips directory exists
$zipsDir = Join-Path $rootDir "zips"
if (-not (Test-Path $zipsDir)) {
    New-Item -ItemType Directory -Path $zipsDir -Force | Out-Null
}

# Zip Archive Generation directly in \zips
$zipName = "$addonName $Version.zip"
$zipPath = Join-Path $zipsDir $zipName

Write-Host "Creating archive zips/$zipName..." -ForegroundColor Cyan
Compress-Archive -Path $addonDir -DestinationPath $zipPath -Force

# Clean up duplicate / legacy zip archives in root
Get-ChildItem -Path $rootDir -Filter "*.zip" -File | ForEach-Object {
    $targetInZips = Join-Path $zipsDir $_.Name
    if (-not (Test-Path $targetInZips)) {
        Move-Item -Path $_.FullName -Destination $targetInZips -Force
        Write-Host "Moved legacy archive to zips/$($_.Name)" -ForegroundColor Cyan
    } else {
        Remove-Item -Path $_.FullName -Force
        Write-Host "Removed duplicate root archive: $($_.Name)" -ForegroundColor Yellow
    }
}

Write-Host "Successfully packaged: zips/$zipName" -ForegroundColor Green
