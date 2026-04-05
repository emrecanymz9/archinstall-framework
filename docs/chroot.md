# Chroot Execution Model

## Rule

All variables used inside chroot MUST be passed via `/root/.install_env` and sourced at runtime.

Direct variable interpolation inside heredoc, including patterns such as `arch-chroot /mnt <<EOF`, is FORBIDDEN.

## Rationale

- heredoc interpolation can occur on the host instead of inside the target system
- escaped variables can pass through as literal strings and fail without an obvious syntax error
- silent expansion failures break determinism in locale, user, and service configuration
- direct interpolation violates the state-driven architecture by bypassing the explicit runtime boundary

The `TARGET_LOCALE` failure is the reference case: a value that should have been consumed inside chroot was emitted as a literal string, which corrupted locale generation and caused downstream postinstall failures.

## Flow

```text
executor -> writes /mnt/root/.install_env
        -> arch-chroot
        -> chroot scripts source /root/.install_env
        -> logic executes against sourced runtime state
```

## Responsibilities

### Executor

- read canonical values from `installer/state.sh`
- validate required runtime inputs before chroot handoff
- generate `/mnt/root/.install_env`
- invoke `arch-chroot` deterministically

### Chroot scripts

- source `/root/.install_env` before reading runtime variables
- fail fast when required values are missing or invalid
- treat sourced environment values as the only supported runtime input channel
- apply passwords, display-manager setup, and service enablement only after the environment is loaded

## Password Application

Password application is a chroot-only responsibility.

Current order:

1. create the primary user
2. normalize `/etc/shadow` ownership and mode
3. set root password
4. set user password

Current implementation rules:

- non-empty passwords use `chpasswd`
- empty passwords use `passwd -d`
- password operations log their exit codes
- any password failure aborts the install

This ordering prevents late chroot failures caused by missing users, bad shadow permissions, or password writes occurring before account creation.

## Required Pattern

```bash
# host side
install_env_path=/mnt/root/.install_env

# chroot side
source /root/.install_env
echo "$TARGET_LOCALE"
useradd -m -G wheel -s /bin/bash "$TARGET_USERNAME"
```

## Forbidden Pattern

```bash
arch-chroot /mnt <<EOF
echo "$TARGET_LOCALE"
useradd -m -G wheel -s /bin/bash "$TARGET_USERNAME"
EOF
```

This pattern is forbidden even when it appears to work. It couples host-side expansion to chroot execution, makes quoting brittle, and produces non-deterministic failures when variables are escaped, empty, or partially validated.

## Common Pitfalls

- escaped variables such as `\$TARGET_LOCALE` or `\$TARGET_USERNAME` produce literal strings instead of runtime expansion
- missing validation before chroot can turn empty state values into destructive or invalid commands
- mixing persisted state reads with ad hoc shell interpolation makes failures harder to trace
- adding new chroot snippets without sourcing `/root/.install_env` creates inconsistent execution paths
- running password or display-manager logic outside chroot breaks the runtime contract

## Engineering Constraint

The environment file is a runtime projection of state, not a replacement for state storage.

- persisted decisions belong in `installer/state.sh`
- environment injection belongs in `installer/executor.sh`
- chroot consumers must remain pure execution layers over the sourced environment

Any new chroot integration must follow this contract.