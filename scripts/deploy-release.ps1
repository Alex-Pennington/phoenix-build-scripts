#!/usr/bin/env pwsh
# deploy-release.ps1
# Phoenix Build System - Automated Release Deployment
#
# Reads phoenix-build.json from project root, bumps version, builds, packages,
# and deploys to GitHub releases.
#
# Usage:
#   .\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch
#   .\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementMinor -Deploy

param(
    [switch]$IncrementMajor,
    [switch]$IncrementMinor,
    [switch]$IncrementPatch,
    [switch]$Deploy,
    [string]$ConfigFile = "phoenix-build.json"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Phoenix Build System - Release Deployment ===" -ForegroundColor Cyan
Write-Host ""

#============================================================================
# Locate project root (where phoenix-build.json lives)
#============================================================================

$projectRoot = Get-Location
$configPath = Join-Path $projectRoot $ConfigFile

if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    Write-Host ""
    Write-Host "Create phoenix-build.json in your project root with:" -ForegroundColor Yellow
    Write-Host @"
{
    "projectName": "my-project",
    "githubRepo": "username/repo-name",
    "executables": ["my_tool.exe"],
    "dlls": ["dependency.dll"],
    "packageFiles": ["README.md", "LICENSE", "docs/"]
}
"@ -ForegroundColor Gray
    exit 1
}

#============================================================================
# Load configuration
#============================================================================

Write-Host "[CONFIG] Loading $ConfigFile..." -ForegroundColor Yellow
$config = Get-Content $configPath -Raw | ConvertFrom-Json

$projectName = $config.projectName
$githubRepo = $config.githubRepo
$executables = $config.executables
$dlls = $config.dlls
$packageFiles = $config.packageFiles

Write-Host "  Project: $projectName" -ForegroundColor Gray
Write-Host "  GitHub: $githubRepo" -ForegroundColor Gray
Write-Host ""

#============================================================================
# Parse current version from CMakeLists.txt
#============================================================================

$cmakePath = Join-Path $projectRoot "CMakeLists.txt"
if (-not (Test-Path $cmakePath)) {
    Write-Error "CMakeLists.txt not found at: $cmakePath"
    exit 1
}

$cmakeContent = Get-Content $cmakePath -Raw

if ($cmakeContent -match 'project\([^\n]+VERSION\s+(\d+)\.(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]
    $patch = [int]$matches[3]
} else {
    Write-Error "Cannot parse VERSION from CMakeLists.txt project() command"
    Write-Host "Expected format: project(name VERSION x.y.z ...)" -ForegroundColor Yellow
    exit 1
}

Write-Host "[VERSION] Current version: $major.$minor.$patch" -ForegroundColor Yellow

#============================================================================
# Increment version based on flags
#============================================================================

if ($IncrementMajor) {
    $major++
    $minor = 0
    $patch = 0
    $resetBuild = $true
    Write-Host "  Incrementing MAJOR -> $major.$minor.$patch" -ForegroundColor Green
}
elseif ($IncrementMinor) {
    $minor++
    $patch = 0
    $resetBuild = $true
    Write-Host "  Incrementing MINOR -> $major.$minor.$patch" -ForegroundColor Green
}
elseif ($IncrementPatch) {
    $patch++
    $resetBuild = $false
    Write-Host "  Incrementing PATCH -> $major.$minor.$patch" -ForegroundColor Green
}
else {
    Write-Host "  No version increment (specify -IncrementMajor, -IncrementMinor, or -IncrementPatch)" -ForegroundColor Yellow
    $resetBuild = $false
}

$versionString = "$major.$minor.$patch"

#============================================================================
# Read and increment build number
#============================================================================

$buildNumberFile = Join-Path $projectRoot ".phoenix-build-number"

if (Test-Path $buildNumberFile) {
    $build = [int](Get-Content $buildNumberFile -Raw).Trim()
} else {
    Write-Host "  Creating .phoenix-build-number with value 0" -ForegroundColor Yellow
    $build = 0
}

if ($resetBuild) {
    Write-Host "  Resetting BUILD to 0 (major/minor increment)" -ForegroundColor Yellow
    $build = 0
} else {
    $build++
    Write-Host "  Incrementing BUILD -> $build" -ForegroundColor Green
}

#============================================================================
# Get git commit and dirty status
#============================================================================

Push-Location $projectRoot
try {
    $gitCommit = (git rev-parse --short HEAD 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) {
        $gitCommit = "unknown"
    }
    
    git diff-index --quiet HEAD -- 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $gitDirty = $false
        $dirtyStr = ""
    } else {
        $gitDirty = $true
        $dirtyStr = "-dirty"
    }
} finally {
    Pop-Location
}

$versionFull = "$versionString+$build.$gitCommit$dirtyStr"
$tag = "v$versionString"

Write-Host ""
Write-Host "[VERSION] New version: $versionFull" -ForegroundColor Cyan
Write-Host "[VERSION] Git tag: $tag" -ForegroundColor Cyan
Write-Host ""

#============================================================================
# Validate clean working directory for deployment
#============================================================================

if ($Deploy -and $gitDirty) {
    Write-Host "=== ERROR: Working directory is dirty ===" -ForegroundColor Red
    Write-Host ""
    Write-Host "You cannot deploy a release with uncommitted changes." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Proper release workflow:" -ForegroundColor Cyan
    Write-Host "  1. Commit all changes: git add . && git commit -m 'Your changes'" -ForegroundColor Gray
    Write-Host "  2. Run deploy script: .\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch -Deploy" -ForegroundColor Gray
    Write-Host "  3. Script will automatically commit version bump, tag, and upload release" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

#============================================================================
# Update CMakeLists.txt with new version
#============================================================================

Write-Host "[UPDATE] Updating CMakeLists.txt..." -ForegroundColor Yellow

$newCmakeContent = $cmakeContent -replace '(project\([^\n]+VERSION\s+)\d+\.\d+\.\d+', "`${1}$versionString"
Set-Content $cmakePath $newCmakeContent -NoNewline

#============================================================================
# Update .phoenix-build-number
#============================================================================

Write-Host "[UPDATE] Updating .phoenix-build-number..." -ForegroundColor Yellow
Set-Content $buildNumberFile "$build" -NoNewline

#============================================================================
# Clean and build
#============================================================================

Write-Host "[BUILD] Cleaning build directory..." -ForegroundColor Yellow
if (Test-Path "build") {
    Remove-Item -Recurse -Force "build"
}

Write-Host "[BUILD] Configuring (cmake --preset msys2-ucrt64)..." -ForegroundColor Yellow
cmake --preset msys2-ucrt64
if ($LASTEXITCODE -ne 0) {
    Write-Error "CMake configure failed"
    exit 1
}

Write-Host "[BUILD] Building (cmake --build --preset msys2-ucrt64)..." -ForegroundColor Yellow
cmake --build --preset msys2-ucrt64
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed"
    exit 1
}

#============================================================================
# Verify executables exist
#============================================================================

Write-Host "[VERIFY] Checking executables..." -ForegroundColor Yellow
$buildDir = Join-Path (Join-Path $projectRoot "build") "msys2-ucrt64"

foreach ($exe in $executables) {
    $exePath = Join-Path $buildDir $exe
    if (-not (Test-Path $exePath)) {
        Write-Error "Executable not found: $exePath"
        exit 1
    }
    Write-Host "  ✓ $exe" -ForegroundColor Green
}

#============================================================================
# Create release package
#============================================================================

Write-Host "[PACKAGE] Creating release archive..." -ForegroundColor Yellow
$zipName = "$projectName-windows-$versionString.zip"
$zipPath = Join-Path $projectRoot $zipName

if (Test-Path $zipPath) {
    Remove-Item $zipPath
}

# Collect all files for the package
$releaseFiles = @()

# Add executables
foreach ($exe in $executables) {
    $releaseFiles += Join-Path $buildDir $exe
}

# Add DLLs
foreach ($dll in $dlls) {
    $dllPath = Join-Path $buildDir $dll
    if (Test-Path $dllPath) {
        $releaseFiles += $dllPath
        Write-Host "  ✓ $dll" -ForegroundColor Green
    } else {
        Write-Warning "DLL not found (skipping): $dllPath"
    }
}

# Add package files
foreach ($file in $packageFiles) {
    $filePath = Join-Path $projectRoot $file
    if (Test-Path $filePath) {
        $releaseFiles += $filePath
        Write-Host "  ✓ $file" -ForegroundColor Green
    } else {
        Write-Warning "Package file not found (skipping): $filePath"
    }
}

Compress-Archive -Path $releaseFiles -DestinationPath $zipPath
Write-Host "  Created $zipName" -ForegroundColor Cyan
Write-Host ""

#============================================================================
# Check if this is a dry run or deployment
#============================================================================

if (-not $Deploy) {
    Write-Host "=== BUILD COMPLETE (DRY RUN) ===" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Version: $versionFull" -ForegroundColor Cyan
    Write-Host "Archive: $zipPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To deploy to GitHub:" -ForegroundColor Yellow
    Write-Host "  .\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch -Deploy" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

#============================================================================
# Commit version changes
#============================================================================

Write-Host "[GIT] Committing version updates..." -ForegroundColor Yellow
Push-Location $projectRoot
try {
    git add $cmakePath
    git add $buildNumberFile
    git commit -m "Bump version to $versionFull"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Git commit failed"
        exit 1
    }
    
    git push origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Git push failed"
        exit 1
    }
} finally {
    Pop-Location
}

#============================================================================
# Create and push git tag
#============================================================================

Write-Host "[GIT] Creating tag $tag..." -ForegroundColor Yellow
Push-Location $projectRoot
try {
    # Delete tag if it exists (local and remote)
    $ErrorActionPreference = "Continue"
    git tag -d $tag 2>&1 | Out-Null
    git push origin ":refs/tags/$tag" 2>&1 | Out-Null
    $ErrorActionPreference = "Stop"
    
    # Create new tag
    git tag $tag
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create tag"
        exit 1
    }
    
    git push origin $tag
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to push tag"
        exit 1
    }
} finally {
    Pop-Location
}

#============================================================================
# Upload to GitHub release
#============================================================================

Write-Host "[RELEASE] Uploading to GitHub..." -ForegroundColor Yellow

try {
    # Try to create new release
    gh release create $tag $zipPath `
        --title "$projectName $versionString" `
        --notes "Release $versionFull" `
        --repo $githubRepo 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        # Release might exist, try uploading to existing
        Write-Host "  Release exists, uploading to existing release..." -ForegroundColor Yellow
        gh release upload $tag $zipPath --clobber --repo $githubRepo
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to upload release"
        }
    }
} catch {
    Write-Error "GitHub release upload failed: $_"
    
    # Rollback: delete the pushed tag
    Write-Host "[ROLLBACK] Deleting tag due to release failure..." -ForegroundColor Red
    Push-Location $projectRoot
    try {
        git tag -d $tag 2>&1 | Out-Null
        git push origin ":refs/tags/$tag" 2>&1 | Out-Null
    } finally {
        Pop-Location
    }
    
    exit 1
}

#============================================================================
# Success!
#============================================================================

Write-Host ""
Write-Host "=== DEPLOYMENT COMPLETE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Version: $versionFull" -ForegroundColor Cyan
Write-Host "Tag: $tag" -ForegroundColor Cyan
Write-Host "Release: https://github.com/$githubRepo/releases/tag/$tag" -ForegroundColor Cyan
Write-Host ""
