# Profiles

## Overview

The installer separates install profiles from filesystem choices.

Package defaults are loaded from [config/system.conf](../config/system.conf).

Profiles affect packages and desktop defaults.
They do not force:

- ext4 vs btrfs
- zram on or off

Those remain normal user-configurable settings.

## DAILY

The daily profile is the low-friction workstation preset.

Defaults:

- KDE Plasma
- greetd
- tuigreet
- auto display mode
- `kate` as the editor package

Package tiers:

- hidden base packages from `config/system.conf`
- semi-hidden required packages from `config/system.conf`
- visible workstation packages for the daily profile

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

- selected editor package
- `git`
- `htop`
- `tmux`
- `curl`
- `wget`
- `fastfetch`
- `ripgrep`
- `fd`
- `less`
- `man-db`
- `man-pages`

Optional:

- `code`

The dev profile also adds hidden required packages such as `base-devel`.

## CUSTOM

The custom profile lets the operator choose:

- one editor package: `nano`, `micro`, `vim`, or `kate`
- whether to install `code`
- whether to include these tool groups:
  - `git`
  - `htop`
  - `tmux`
  - `curl` + `wget`
  - `fastfetch`
  - `ripgrep`
  - `fd`
  - `man pages + less`

Hidden base packages, kernel packages, and firmware never appear in the custom UI.

## Package Merge Rules

Final package selection is built from:

- hidden base packages
- semi-hidden required packages
- filesystem requirements
- visible profile packages
- hardware abstraction packages
- Secure Boot tooling packages
- desktop profile packages
- plugin packages

Duplicates are removed before `pacstrap` runs.