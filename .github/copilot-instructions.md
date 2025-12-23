# Phoenix Build Scripts - AI Agent Instructions

**Purpose:** Reusable CMake build system for Phoenix SDR projects providing version management, automated builds, and GitHub release deployment.

## Architecture Overview

This is a **git submodule library** designed to be embedded in consuming projects at `external/phoenix-build-scripts/`. It provides:

1. **CMake module** ([cmake/phoenix-build.cmake](../cmake/phoenix-build.cmake)) - Generates version headers from git state
2. **PowerShell automation** ([scripts/](../scripts/)) - Project initialization and release deployment
3. **Templates** ([templates/](../templates/)) - Bootstrap files for consuming projects

### Version System Architecture

Version format: `MAJOR.MINOR.PATCH+BUILD.COMMIT[-dirty]`

**Multi-source composition:**
- `MAJOR.MINOR.PATCH` from `CMakeLists.txt` `project(VERSION x.y.z)`
- `BUILD` from `.phoenix-build-number` file (tracked in git)
- `COMMIT` from `git rev-parse --short HEAD`
- `-dirty` flag from `git diff-index --quiet HEAD`

**Critical:** [deploy-release.ps1](../scripts/deploy-release.ps1) is the **single source of truth** for version increments. It updates both CMakeLists.txt and .phoenix-build-number atomically.

## Development Workflows (AI Agents MUST follow)

- **Install first:** After adding the submodule, run `scripts/init-project.ps1` (do not hand-create configs).
- **Only build via deploy script:** All builds—dry run or release—must go through `scripts/deploy-release.ps1`. Do not call `cmake` directly.
- **Propagate rules:** When including this repo in another project, copy these instructions into that project’s `.github/copilot-instructions.md`.

### Local Build / Dry Run (consuming project)
```powershell
# Builds, packages, no commit/tag/upload
.\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch
```

### Release Deployment (consuming project)
```powershell
# Commit your changes first, then:
.\external\phoenix-build-scripts\scripts\deploy-release.ps1 -IncrementPatch -Deploy
```

**What deploy-release.ps1 does (single source of truth):**
1. Updates `CMakeLists.txt` VERSION → new semver
2. Updates/increments `.phoenix-build-number`
3. Clean rebuild (deletes `build/`)
4. Creates ZIP with executables + DLLs + docs (per [phoenix-build.json](../templates/phoenix-build.json))
5. Commits version files with message "Bump version to x.y.z+N.hash"
6. Pushes to `main`
7. Creates git tag `vX.Y.Z` and pushes it
8. Uploads release ZIP via `gh`

**Rollback:** If GitHub upload fails, the script deletes the pushed tag.

### Project Initialization (consuming project)
```powershell
.\external\phoenix-build-scripts\scripts\init-project.ps1 `
    -ProjectName "my-sdr-tool" `
    -GitHubRepo "user/repo" `
    -Executables @("tool.exe") `
    -PackageFiles @("README.md", "LICENSE")
```

This installs required config: `CMakePresets.json`, `cmake/version.h.in`, `phoenix-build.json`, `.phoenix-build-number`.

## Critical Conventions

### 1. Version Header Generation Flow
```
templates/version.h.in → [phoenix-build.cmake] → build/include/version.h
                              ↑ reads
                    CMakeLists.txt project(VERSION)
                    .phoenix-build-number
                    git rev-parse
```

Consumer code: `#include <version.h>` then use `PHOENIX_VERSION_FULL` or `print_version("app_name")`.

### 2. Build Number Reset Rules
- Patch increment (`-IncrementPatch`): BUILD increments (5 → 6)
- Minor/Major increment: BUILD **resets to 0**

Implementation: [deploy-release.ps1](../scripts/deploy-release.ps1) lines 120-135.

### 3. Dirty Working Directory Enforcement
[deploy-release.ps1](../scripts/deploy-release.ps1) line 175: Exits with error if `-Deploy` is used with uncommitted changes. This ensures releases are always reproducible from git tags.

### 4. CMake Integration Pattern (handled by scripts; do not run CMake manually)
Consuming projects must:
1. Include AFTER `project()` command: `include(external/phoenix-build-scripts/cmake/phoenix-build.cmake)`
2. Ensure `cmake/version.h.in` exists (init-project script copies it; otherwise the module falls back to external/templates)
3. Consume generated `build/include/version.h` (added to include path by the module)

## File Responsibilities

| File | Modifies | Reads | Purpose |
|------|----------|-------|---------|
| [phoenix-build.cmake](../cmake/phoenix-build.cmake) | `build/include/version.h` | CMakeLists.txt VERSION, .phoenix-build-number, git | Generate version header at configure time |
| [deploy-release.ps1](../scripts/deploy-release.ps1) | CMakeLists.txt, .phoenix-build-number, git tags | phoenix-build.json | Orchestrate releases |
| [init-project.ps1](../scripts/init-project.ps1) | Consuming project files | templates/ | Bootstrap new projects |

## External Dependencies

**Required for consuming projects:**
- MSYS2 UCRT64 environment (CMake, GCC, Ninja)
- PowerShell 5.1+ (scripts use native .NET JSON parsing)
- GitHub CLI (`gh`) authenticated for `-Deploy` flag
- Git (version detection, tagging)

**CMakePresets.json assumption:** Uses Ninja generator. If modifying, update [templates/CMakePresets.json](../templates/CMakePresets.json) line 18.

## Common Pitfalls

1. **Don't manually edit version.h** - It's auto-generated. Edit [templates/version.h.in](../templates/version.h.in) instead.
2. **Don't commit without deploying** - Version bumps should be atomic with tag creation via deploy script, not manual edits.
3. **phoenix-build.json paths are relative to project root** - `packageFiles` like `"docs/"` resolves from consuming project, not phoenix-build-scripts.
4. **CMakeLists.txt VERSION must be x.y.z format** - Script regex on line 73 of deploy-release.ps1 expects 3 digits.

## Testing Changes to This Repository

When modifying phoenix-build-scripts itself:
1. Test in a consuming project (phoenix-sdr-net recommended)
2. Create feature branch in consuming project pointing to phoenix-build-scripts branch
3. Run full release cycle with `-Deploy` omitted (dry run)
4. Verify `build/include/version.h` generation correctness
