# Repository Guidelines

## Project Structure & Module Organization

This repository contains an experimental native UI framework for Odin, targeting macOS, iOS, Android, Linux, and Windows.

- `nv/`: shared API in `nv.odin`, backend contract in `backend.odin`, and native implementations named `<feature>_<platform>.odin`.
- `app/`: shared example application; keep it free of platform-specific code. Images and fonts live in `app/assets/`.
- `nv/*_test.odin`: core tests and mock backend.
- `tools/nvbuild/`: cross-platform build tool; `tools/hooks/`: optional Git hooks.
- `android/`, `ios/`, `windows/`: packaging resources and platform tooling. Android Java shims live in `nv/android/java/nv/`.
- `build/<platform>/`: generated build output. Consult `CLAUDE.md` for detailed architecture and platform constraints.

## Build, Test, and Development Commands

Use the Odin version pinned by `ODIN_PIN` in `tools/nvbuild/main.odin`; platform builds also require their native SDKs or libraries.

- `odin run tools/nvbuild -- build`: build, package, and launch the host example.
- `odin run tools/nvbuild -- build --platform=ios --no-run`: package for the iOS simulator without launching. Add `--release` for optimization.
- `odin run tools/nvbuild -- check --platform=all`: type-check all targets with `-vet -strict-style`, including tooling.
- `odin run tools/nvbuild -- test`: run host core tests.
- `odin run tools/nvbuild -- ci`: run all-target checks followed by tests; run before pushing.

Enable the optional pre-push check with `git config core.hooksPath tools/hooks`. There is no hosted CI.

## Coding Style & Naming Conventions

Match existing Odin code: tabs for indentation, `snake_case` procedures and variables, `Title_Case` types, and uppercase constants. Preserve widget API patterns such as `Label`, `Label_Handle`, `label_create`, and `label_set_text`. Keep native behavior in platform backends and use compiler strict-style checks for validation.

## Testing Guidelines

Use `core:testing`, `@(test)`, and descriptive `test_*` procedures in `*_test.odin`. Mock-based fixtures use `mock_begin(t)` and deferred `mock_end(t)`. Tests run single-threaded because core state is global, with bad-memory checking enabled. Add regression coverage for core behavior changes; no numerical coverage threshold is specified. Native backend changes also require manual interaction on affected platforms.

## Commit & Pull Request Guidelines

History uses short, descriptive subjects, often prefixed by a component, such as `nvbuild:` or `docs:`. Follow that pattern. In pull requests, explain the behavior change, affected platforms, and validation performed; link relevant issues and include screenshots for visible UI changes.
