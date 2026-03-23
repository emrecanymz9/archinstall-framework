# Plugins

## Overview

Plugins live under [installer/plugins](../installer/plugins).

Each plugin is discovered from:

- `installer/plugins/*/plugin.sh`

The loader syntax-checks each plugin before sourcing it.
Plugins are optional. A broken plugin must not abort the installer.

Core implementation:

- [installer/core/plugin-loader.sh](../installer/core/plugin-loader.sh)
- [installer/core/hooks.sh](../installer/core/hooks.sh)

## Supported Capabilities

Plugins can currently:

- register lifecycle hooks with `register_hook`
- inject additional packages with `register_plugin_packages`
- inject extra chroot script content with `register_chroot_snippet`
- extend installer menus with `register_menu_entry`

## Lifecycle Hooks

Available hook names:

- `pre_disk`
- `post_disk`
- `pre_install`
- `post_chroot`
- `post_install`

Example:

```bash
my_plugin_pre_install() {
	log_debug "my plugin ran before installation"
	return 0
}

register_hook pre_install my_plugin_pre_install || true
```

Hook failures are logged as warnings and do not stop the installer.

## Package Injection

Use `register_plugin_packages` to add packages to the final `pacstrap` list.

```bash
register_plugin_packages my-package another-package || true
```

## Chroot Extension

Use `register_chroot_snippet` to append shell content into the generated chroot configuration script.

```bash
register_chroot_snippet 'echo "plugin chroot step" >> /root/plugin.log' || true
```

The snippet should be idempotent and tolerant of missing binaries.

## UI Extension

Plugins can add menu entries to these menus:

- `main`
- `disk`
- `install`

Example:

```bash
my_plugin_menu() {
	msg "Plugin" "Hello from a plugin menu entry."
	return 0
}

register_menu_entry install plugin-info "Plugin Info" my_plugin_menu || true
```

If a menu handler fails, the installer logs the failure and returns to the menu.

## Safety Rules

- Always treat installer modules as optional.
- Check command availability before using non-base tools.
- Return success when skipping optional behavior.
- Avoid destructive disk actions outside the normal installer flow.