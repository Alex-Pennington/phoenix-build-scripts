# Phoenix Build Scripts

**Version:** v1.0.0  
**Developer:** Alex Pennington (KY4OLB)  
**License:** AGPL-3.0

Reusable build system for Phoenix SDR projects providing standardized CMake configuration, automated version management, and GitHub release deployment.

---

## Overview

**Phoenix Build Scripts** is a git submodule that provides consistent build infrastructure across all Phoenix projects. It handles version management (MAJOR.MINOR.PATCH+BUILD.COMMIT-dirty), automated builds with MSYS2/CMake, and deployment to GitHub releases.

## AI Agent Protocol (MANDATORY)

- Follow this repository’s protocol only; do not invent alternate build flows.
- **All builds must go through** `scripts/deploy-release.ps1` (dry run or `-Deploy`). Do not call `cmake` directly.
- **Installation is required:** run `scripts/init-project.ps1` immediately after adding the submodule. Do not hand-create config files.
- When you include this repo, copy the build instructions into your project’s `.github/copilot-instructions.md` so agents see them early.

### Key Features

- **Standardized CMake presets** - msys2-ucrt64, debug, release configurations
- **Automated version management** - Semantic versioning with build numbers and git tracking
- **Deployment automation** - One-command release builds with GitHub integration
- **Project-agnostic** - Configure via simple JSON file, use as submodule or reference
- **No CI/CD required** - Manual builds with local control, GitHub just hosts releases

---

## Quick Start

### 1. Add as Submodule

```bash
cd your-phoenix-project
git submodule add https://github.com/Alex-Pennington/phoenix-build-scripts external/phoenix-build-scripts
git submodule update --init --recursive
```

### 2. Install (initialize) via script — required

```powershell
.\external\phoenix-build-scripts\scripts\init-project.ps1 `
    -ProjectName "my-phoenix-project" `
    -GitHubRepo "username/repository-name" `
    -Executables @("my_tool.exe") `
    -PackageFiles @("README.md", "LICENSE", "docs/")
```

This script installs all required config:
- `CMakePresets.json` - Standard build presets
- `cmake/version.h.in` - Version header template
- `phoenix-build.json` - Project configuration
- `.phoenix-build-number` - Build counter (starts at 0)

### 3. Integrate with CMakeLists.txt

Add this line **after** your `project()` command (no manual `cmake` runs required; the build script drives CMake):

```cmake
project(my-phoenix-project
    VERSION 0.1.0
    DESCRIPTION "My Phoenix SDR Project"
    LANGUAGES C
)

# Phoenix Build System integration
include(external/phoenix-build-scripts/cmake/phoenix-build.cmake)
```

### 4. Build and Deploy (only via build script)

```powershell
# Dry run build/package
.\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch

# Deploy to GitHub (also the only approved release build path)
.\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch -Deploy
```

---

## Configuration

### phoenix-build.json

Project-specific configuration file in your repository root:

```json
{
    "projectName": "phoenix-sdr-net",
    "githubRepo": "Alex-Pennington/phoenix-sdr-net",
    "executables": [
        "sdr_server.exe",
        "telem_logger.exe"
    ],
    "dlls": [
        "sdrplay_api.dll"
    ],
    "packageFiles": [
        "README.md",
        "LICENSE",
        "docs/IQ_STREAMING.md"
    ]
}
```

**Fields:**
- `projectName` - Used in ZIP filename: `{projectName}-windows-{version}.zip`
- `githubRepo` - GitHub repository in `owner/repo` format
- `executables` - List of .exe files from `build/msys2-ucrt64/` to package
- `dlls` - List of .dll files from `build/msys2-ucrt64/` to package
- `packageFiles` - Additional files/directories from project root to include

---

## Version Management

### Format

```
MAJOR.MINOR.PATCH+BUILD.COMMIT[-dirty]
```

**Examples:**
- `0.1.2+5.abc1234` - Clean build
- `0.1.2+5.abc1234-dirty` - Uncommitted changes

### Components

| Component | Source | Managed By |
|-----------|--------|------------|
| **MAJOR.MINOR.PATCH** | `CMakeLists.txt` `project(VERSION)` | deploy-release.ps1 |
| **BUILD** | `.phoenix-build-number` file | deploy-release.ps1 |
| **COMMIT** | `git rev-parse --short HEAD` | phoenix-build.cmake |
| **DIRTY** | `git diff-index --quiet HEAD` | phoenix-build.cmake |

### Version Increment Flags

```powershell
# Increment patch (0.1.0 -> 0.1.1), build continues
.\scripts\deploy-release.ps1 -IncrementPatch

# Increment minor (0.1.2 -> 0.2.0), build resets to 0
.\scripts\deploy-release.ps1 -IncrementMinor

# Increment major (0.2.1 -> 1.0.0), build resets to 0
.\scripts\deploy-release.ps1 -IncrementMajor
```

### Build Number Behavior

- **Patch increment**: BUILD increments (5 → 6)
- **Minor increment**: BUILD resets to 0
- **Major increment**: BUILD resets to 0

---

## Deployment Workflow

### Proper Release Process (only via deploy-release.ps1)

1. **Commit all changes:**
    ```bash
    git add .
    git commit -m "Your feature description"
    ```

2. **Run deployment script (the only approved build path):**
    ```powershell
    .\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch -Deploy
    ```

3. **Script automatically:**
    - Updates `CMakeLists.txt` version
    - Increments `.phoenix-build-number`
    - Rebuilds project
    - Creates ZIP package
    - Commits version changes
    - Creates and pushes git tag (e.g., `v0.1.2`)
    - Uploads release to GitHub

### Dry Run (No Deployment)

Omit the `-Deploy` flag to test locally; this is the only approved dry-run build path. It builds and packages but doesn't commit, tag, or upload to GitHub:

```powershell
.\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch
```

### Error Handling

If deployment fails with dirty working directory:

```
=== ERROR: Working directory is dirty ===

Proper release workflow:
  1. Commit all changes: git add . && git commit -m 'Your changes'
  2. Run deploy script: .\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch -Deploy
```

If GitHub release upload fails, the script **automatically rolls back** the git tag.

---

## CMake Integration

### What phoenix-build.cmake Does

1. Reads version from `project(VERSION x.y.z)` in CMakeLists.txt
2. Reads build number from `.phoenix-build-number`
3. Detects git commit hash and dirty status
4. Generates `build/include/version.h` from `cmake/version.h.in`
5. Adds `build/include/` to include paths

### Using Version in Your Code

```c
#include <version.h>

int main(int argc, char *argv[]) {
    print_version("my_tool");  // Uses inline helper from version.h
    
    // Or manually:
    printf("Version: %s\n", PHOENIX_VERSION_FULL);
    printf("Build: %d\n", PHOENIX_VERSION_BUILD);
    printf("Commit: %s\n", PHOENIX_GIT_COMMIT);
    
    return 0;
}
```

**Output:**
```
my_tool v0.1.2+5.abc1234 (built Dec 23 2025 14:30:15)
```

---

## Project Structure

### Typical Phoenix Project Layout

```
my-phoenix-project/
├── .github/                    # Optional GitHub workflows (future)
├── .gitignore
├── .gitmodules                 # Submodule references
├── CMakeLists.txt
├── CMakePresets.json           # Copied from phoenix-build-scripts
├── LICENSE
├── README.md
├── phoenix-build.json          # Project-specific configuration
├── .phoenix-build-number       # Build counter (tracked in git)
├── cmake/
│   └── version.h.in            # Copied from phoenix-build-scripts
├── docs/
│   └── PROTOCOL.md
├── external/
│   └── phoenix-build-scripts/  # This repository (submodule)
├── include/
│   └── my_lib.h
└── src/
    └── main.c
```

### Generated During Build

```
build/
├── msys2-ucrt64/
│   ├── my_tool.exe
│   ├── dependency.dll
│   └── ...
└── include/
    └── version.h               # Generated from cmake/version.h.in
```

---

## Requirements

### Development Environment

- **Windows**: MSYS2 with UCRT64 environment
  - Install: https://www.msys2.org/
  - Packages: `mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja`
  
- **PowerShell**: Core 7+ (cross-platform) or Windows PowerShell 5.1

- **Git**: For version control and submodules

- **GitHub CLI** (`gh`): For release uploads
  - Install: `scoop install gh` or https://cli.github.com/
  - Authenticate: `gh auth login`

### CMake Requirements

- **Minimum version**: 3.16
- **Generator**: Ninja (recommended for speed)

---

## Scripts Reference

### deploy-release.ps1

Automated release deployment script.

**Location:** `external/phoenix-build-scripts/scripts/deploy-release.ps1`

**Usage:**
```powershell
.\external\phoenix-build-scripts\scripts\deploy-release.ps1 [flags]
```

**Flags:**
- `-IncrementMajor` - Bump major version, reset minor/patch/build to 0
- `-IncrementMinor` - Bump minor version, reset patch to 0, reset build to 0
- `-IncrementPatch` - Bump patch version, increment build
- `-Deploy` - Actually deploy to GitHub (otherwise dry run)
- `-ConfigFile` - Path to phoenix-build.json (default: `phoenix-build.json`)

**Examples:**
```powershell
# Dry run patch increment
.\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch

# Deploy patch increment
.\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch -Deploy

# Deploy minor increment
.\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementMinor -Deploy
```

### init-project.ps1

Initialize a new project with Phoenix Build System.

**Location:** `external/phoenix-build-scripts/scripts/init-project.ps1`

**Usage:**
```powershell
.\external\phoenix-build-scripts\scripts\init-project.ps1 `
    -ProjectName "my-project" `
    -GitHubRepo "username/repo" `
    -Executables @("tool.exe") `
    -DLLs @("lib.dll") `
    -PackageFiles @("README.md", "LICENSE")
```

**Parameters:**
- `-ProjectName` - Name used in ZIP filename (required)
- `-GitHubRepo` - GitHub repository in owner/repo format (required)
- `-Executables` - Array of executable names to package
- `-DLLs` - Array of DLL names to package
- `-PackageFiles` - Array of files/directories to include in release

---

## Templates

All templates are in `templates/` directory:

- **CMakePresets.json** - Standard build presets
- **version.h.in** - Version header template
- **phoenix-build.json** - Example configuration

Copy templates manually or use `init-project.ps1` to bootstrap.

---

## Troubleshooting

### "phoenix-build.json not found"

Run from project root or specify path (always via deploy-release.ps1):
```powershell
.\external\phoenix-build-scripts\scripts\deploy-release.ps1 -ConfigFile "path/to/phoenix-build.json"
```

### "Cannot parse VERSION from CMakeLists.txt"

Ensure your `project()` command includes VERSION:
```cmake
project(my-project VERSION 0.1.0 LANGUAGES C)
```

### "Executable not found"

Check that executable names in `phoenix-build.json` match output:
```powershell
ls build/msys2-ucrt64/*.exe
```

### "gh: command not found"

Install GitHub CLI:
```bash
# MSYS2
pacman -S github-cli

# Or download from https://cli.github.com/
```

Then authenticate:
```bash
gh auth login
```

---

## License

This project is licensed under the **GNU Affero General Public License v3.0** (AGPL-3.0).

See [LICENSE](LICENSE) file for details.

---

## Contributing

This repository is part of the Phoenix Nest MARS Communications Suite.

For issues or improvements:
1. Create an issue on GitHub
2. Submit a pull request
3. Contact Alex Pennington (KY4OLB)

---

## Future Work

- Linux/bash equivalent of deploy-release.ps1
- GitHub Actions workflow templates (optional)
- Multi-platform packaging (Linux .tar.gz, etc.)
- Documentation generation automation
