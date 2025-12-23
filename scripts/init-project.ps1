#!/usr/bin/env pwsh
# init-project.ps1
# Phoenix Build System - Project Initialization
#
# Copies templates and configures a new project to use phoenix-build-scripts
#
# Usage (from project root):
#   .\external\phoenix-build-scripts\scripts\init-project.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,
    
    [Parameter(Mandatory=$true)]
    [string]$GitHubRepo,
    
    [string[]]$Executables = @("my_program.exe"),
    [string[]]$DLLs = @(),
    [string[]]$PackageFiles = @("README.md", "LICENSE")
)

$ErrorActionPreference = "Stop"

Write-Host "=== Phoenix Build System - Project Initialization ===" -ForegroundColor Cyan
Write-Host ""

$projectRoot = Get-Location
$scriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildScriptsRoot = Split-Path -Parent $scriptsDir

Write-Host "[INFO] Project root: $projectRoot" -ForegroundColor Gray
Write-Host "[INFO] Build scripts: $buildScriptsRoot" -ForegroundColor Gray
Write-Host ""

#============================================================================
# Copy CMakePresets.json
#============================================================================

$presetsSource = Join-Path (Join-Path $buildScriptsRoot "templates") "CMakePresets.json"
$presetsDest = Join-Path $projectRoot "CMakePresets.json"

if (Test-Path $presetsDest) {
    Write-Host "[SKIP] CMakePresets.json already exists" -ForegroundColor Yellow
} else {
    Copy-Item $presetsSource $presetsDest
    Write-Host "[COPY] CMakePresets.json" -ForegroundColor Green
}

#============================================================================
# Copy version.h.in to cmake/ directory
#============================================================================

$cmakeDir = Join-Path $projectRoot "cmake"
if (-not (Test-Path $cmakeDir)) {
    New-Item -ItemType Directory -Path $cmakeDir | Out-Null
    Write-Host "[CREATE] cmake/" -ForegroundColor Green
}

$versionSource = Join-Path (Join-Path $buildScriptsRoot "templates") "version.h.in"
$versionDest = Join-Path $cmakeDir "version.h.in"

if (Test-Path $versionDest) {
    Write-Host "[SKIP] cmake/version.h.in already exists" -ForegroundColor Yellow
} else {
    Copy-Item $versionSource $versionDest
    Write-Host "[COPY] cmake/version.h.in" -ForegroundColor Green
}

#============================================================================
# Create phoenix-build.json
#============================================================================

$configPath = Join-Path $projectRoot "phoenix-build.json"

if (Test-Path $configPath) {
    Write-Host "[SKIP] phoenix-build.json already exists" -ForegroundColor Yellow
} else {
    $config = @{
        projectName = $ProjectName
        githubRepo = $GitHubRepo
        executables = $Executables
        dlls = $DLLs
        packageFiles = $PackageFiles
    }
    
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath
    Write-Host "[CREATE] phoenix-build.json" -ForegroundColor Green
}

#============================================================================
# Create .phoenix-build-number
#============================================================================

$buildNumberPath = Join-Path $projectRoot ".phoenix-build-number"

if (Test-Path $buildNumberPath) {
    Write-Host "[SKIP] .phoenix-build-number already exists" -ForegroundColor Yellow
} else {
    Set-Content $buildNumberPath "0" -NoNewline
    Write-Host "[CREATE] .phoenix-build-number (initialized to 0)" -ForegroundColor Green
}

#============================================================================
# Create .gitignore entries
#============================================================================

$gitignorePath = Join-Path $projectRoot ".gitignore"
$gitignoreContent = @"

# Phoenix Build System
build/
install/
*.zip
"@

if (Test-Path $gitignorePath) {
    $currentGitignore = Get-Content $gitignorePath -Raw
    if ($currentGitignore -notlike "*Phoenix Build System*") {
        Add-Content $gitignorePath $gitignoreContent
        Write-Host "[UPDATE] .gitignore (added build system entries)" -ForegroundColor Green
    } else {
        Write-Host "[SKIP] .gitignore already has Phoenix Build System entries" -ForegroundColor Yellow
    }
} else {
    Set-Content $gitignorePath $gitignoreContent
    Write-Host "[CREATE] .gitignore" -ForegroundColor Green
}

#============================================================================
# Print integration instructions
#============================================================================

Write-Host ""
Write-Host "=== INITIALIZATION COMPLETE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Add this to your CMakeLists.txt after project() command:" -ForegroundColor Yellow
Write-Host ""
Write-Host @"
    # Phoenix Build System integration
    include(external/phoenix-build-scripts/cmake/phoenix-build.cmake)
"@ -ForegroundColor Gray
Write-Host ""
Write-Host "2. Update phoenix-build.json with your executables and package files" -ForegroundColor Yellow
Write-Host ""
Write-Host "3. Configure and build your project:" -ForegroundColor Yellow
Write-Host "   cmake --preset msys2-ucrt64" -ForegroundColor Gray
Write-Host "   cmake --build --preset msys2-ucrt64" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Deploy a release:" -ForegroundColor Yellow
Write-Host "   .\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch -Deploy" -ForegroundColor Gray
Write-Host ""
