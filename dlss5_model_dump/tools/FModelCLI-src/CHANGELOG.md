# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Critical: Patch PAK content overwritten by base PAK during export**
  - `FileProviderDictionary.GetEnumerator()` yields ALL entries from ALL PAKs
    (including duplicates) in descending `ReadOrder`. Patch PAKs (`_P.pak`,
    `ReadOrder = base + 100*version`) appear first, but without deduplication
    the subsequent base entry overwrites the correct patch file on disk.
  - Added `HashSet<string>` deduplication in the export loop: the first
    occurrence (highest `ReadOrder` = patch) is authoritative; duplicates are
    skipped. This ensures `File.WriteAllBytes` is only called once per virtual
    path with the correct (patch-priority) content.
  - Affected scenario: Wuthering Waves CN v3.1 — 8,427 ConfigDB entries had
    empty EN translations in the base PAK; the Resource Patch PAK contained
    the filled translations but was being overwritten.

### Added
- Initial release of FModelCLI
- Single-file executable for Windows x64
- Support for AES-encrypted PAK files
- Multiple AES key support (comma/semicolon separated)
- File filtering by keyword
- Automated build script (`sync_upstream.ps1`)
- Comprehensive documentation

### Changed
- N/A

### Deprecated
- N/A

### Removed
- N/A

### Fixed
- N/A

### Security
- N/A

## [1.0.0] - 2026-01-27

### Added
- Initial public release
- Command-line interface for FModel/CUE4Parse
- Support for Wuthering Waves and other UE4/UE5 games
- Self-contained .NET 8.0 executable
- GPL-3.0 License (required by FModel dependency)
- GitHub Actions CI/CD pipeline

---

## Version History Format

Each version should include:
- **Added** for new features
- **Changed** for changes in existing functionality
- **Deprecated** for soon-to-be removed features
- **Removed** for now removed features
- **Fixed** for any bug fixes
- **Security** for vulnerability fixes

Example entry:
```markdown
## [1.1.0] - 2026-02-15

### Added
- Support for UE5.3 games
- Progress bar for large extractions

### Fixed
- Crash when output directory doesn't exist
- Memory leak in large file processing
```
