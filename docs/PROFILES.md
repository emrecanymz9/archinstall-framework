# Profiles

## Overview

The installer separates install profiles from filesystem choices.

Profiles affect packages and desktop defaults.
They do not force:

- ext4 vs btrfs
- zram on or off

Those remain normal user-configurable settings.

## DAILY

The daily profile is the low-friction workstation preset.

Defaults:

- KDE Plasma
- SDDM
- auto display mode
- `kate` as the editor package

Adds a general workstation toolset including:

- `nano`
- `curl`
- `wget`
- `htop`
- `tmux`
- `unzip`
- `p7zip`
- `rsync`
- `less`
- `man-db`
- `man-pages`
- `fastfetch`

## DEV

The developer profile keeps desktop selection flexible but adds a development-oriented package set.

Includes:

- `nano`
- `micro`
- `vim`
- `htop`
- `tmux`
- `ripgrep`
- `fd`
- `less`
- `man-db`
- `man-pages`

Optional:

- `code`

The base system already includes `git` and `base-devel`.

## CUSTOM

The custom profile lets the operator choose:

- one editor package: `nano`, `micro`, `vim`, or `kate`
- whether to install `code`
- whether to include these tool groups:
  - `git`
  - `base-devel`
  - `htop`
  - `tmux`
  - `curl` + `wget`
  - `fastfetch`

## Package Merge Rules

Final package selection is built from:

- base install packages
- filesystem requirements
- install profile packages
- hardware abstraction packages
- Secure Boot tooling packages
- desktop profile packages

Duplicates are removed before `pacstrap` runs.