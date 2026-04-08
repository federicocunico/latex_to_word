#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Downloads the latest pandoc release binary for Windows.

.DESCRIPTION
    Fetches the latest pandoc release from GitHub and places pandoc.exe
    at flutter_app/pandoc/windows/pandoc.exe, ready for the CMake build.

.EXAMPLE
    .\scripts\download_pandoc.ps1
    .\scripts\download_pandoc.ps1 -Version 3.6.4
#>

param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

$outDir = Join-Path $PSScriptRoot "..\pandoc\windows"
$outFile = Join-Path $outDir "pandoc.exe"

if (Test-Path $outFile) {
    Write-Host "pandoc.exe already present at $outFile — skipping download."
    exit 0
}

# Resolve version
if ($Version -eq "") {
    Write-Host "Fetching latest pandoc release info from GitHub..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/jgm/pandoc/releases/latest"
    $Version = $release.tag_name
}

Write-Host "Downloading pandoc $Version for Windows..."

$zipName = "pandoc-$Version-windows-x86_64.zip"
$url = "https://github.com/jgm/pandoc/releases/download/$Version/$zipName"
$tmpZip = Join-Path $env:TEMP $zipName
$tmpDir = Join-Path $env:TEMP "pandoc_extract"

Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
Expand-Archive -Path $tmpZip -DestinationPath $tmpDir

# Find pandoc.exe inside the extracted directory
$pandocExe = Get-ChildItem -Recurse -Path $tmpDir -Filter "pandoc.exe" |
    Where-Object { $_.Name -eq "pandoc.exe" } |
    Select-Object -First 1

if ($null -eq $pandocExe) {
    Write-Error "pandoc.exe not found in downloaded archive."
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Copy-Item -Path $pandocExe.FullName -Destination $outFile

Remove-Item $tmpZip -Force
Remove-Item $tmpDir -Recurse -Force

Write-Host "pandoc $Version installed to $outFile"
