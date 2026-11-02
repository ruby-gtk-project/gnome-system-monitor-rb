# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## [Unreleased]

### Added

- Per-process icons in the process table, ported from `src/prettytable.cpp` and
  `src/defaulttable.h`: the owning application's icon, the icon theme under the
  process name, the table of well-known commands, a kernel-thread icon and a
  plain executable fallback, re-resolved when the icon theme changes.
- Adaptive process-list refresh behind the "Enable Smooth Refresh" switch,
  ported from `src/smooth_refresh.cpp`.
- The reduced primary menu (`generic-window-menu` of `data/menus.ui`) on the
  Resources and File Systems pages.
- The KDE desktop entry, `data/gnome-system-monitor-kde.desktop`.
- The colour-button arrow overlay assets in `data/pixmaps/`.
- The user manual `app.help` opens: upstream's help pages, their translations,
  and `make help` to merge the two with itstool.

### Changed

### Deprecated

### Removed

### Fixed

- `make run` and `make install` looked for the executables under `bin/`, where
  they have not lived since the gem packaging moved them to `exe/`.

### Security

[Unreleased]: https://gitlab.com/ruby-gtk-project/gnome-system-monitor-rb/-/compare/HEAD
