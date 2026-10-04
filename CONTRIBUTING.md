# Contributing to Niveth Linux

Thank you for contributing to Niveth Linux.

## Development Workflow

Start from the latest `main` branch and create a new branch for your work.
Example branches:

```text
fix-calamares-storage
update-vivaldi-theme
improve-app-center
update-wallpapers
```

## Before Committing

Do not commit generated ISO y§s, build output, temporary files, development backups, cache files, or personal credentials and secrets.

Run:
```text
./scripts/build-snapshot-iso.sh --preflight
```

For build-related changes also test:

```text
./scripts/build-snapshot-iso.sh --build
```

## Pull Requests

Open a Pull Request from your branch into `main`. Reviewers may request changes before merging.

## Keep Changes Focused

Keep each Pull Request focused on one feature, bug fix, cleanup, or clearly defined change.

## Project Structure
```text
branding/   Operating-system branding
desktop/   Desktop configuration and assets
installer/  Calamares configuration and branding
packages/   Package definitions
scripts/    Build, setup and validation scripts
tests/      Test files
tools/      Development tools
```

## License

Niveth Linux licensing information will be added as the project develops.
