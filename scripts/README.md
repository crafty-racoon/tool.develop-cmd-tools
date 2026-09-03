# Develop CMD Tools

The parent directory is one portable development-tool bundle. Copy that entire folder
to another repository; none of its PowerShell scripts resolve the project from
their own installation path.

## Entry points

- `Git Operations.cmd [project-root]` operates on a Git repository and all of
  its recursive submodules. If omitted, `project-root` is the current directory.
- `Run Tests.cmd` runs the interactive commit, dependency, and suite workflow.
- `Build And Test.cmd` runs the same workflow and builds first.

For either test entry point, launch it while the current directory is the target
repository. A wrapper may instead set `DEVELOP_CMD_PROJECT_ROOT` first.

## Project configuration

Git operations are project-neutral. After copying, edit
`scripts/develop-cmd-tools.json` to define the project name, build and test scripts,
result directory, suite labels/arguments, and optional dependency-preparation
command. Optional dependency-pin updates expect Git submodules whose dependency
manifests are named `dependencies.json`.

Requirements: Git, Windows PowerShell, and the target project's own build/test
runtime (for NarrativeEditor, the pinned .NET SDK).

## Package and install

Run `Pack.cmd` to create a versioned ZIP and SHA-256 file. Run
`Install Or Update.cmd C:\path\to\project` to install or update from the main
branch. Add `-Version 1.0.0` after the project path to install a release tag, or
use `-PackagePath C:\path\to\package.zip` for an offline package.

The first installation creates `scripts/develop-cmd-tools.local.json`. Edit that
file for the target project; later updates preserve it.
