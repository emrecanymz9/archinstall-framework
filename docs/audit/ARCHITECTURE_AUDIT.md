# Architecture Audit

## Summary
This installer is no longer a simple script. It is a modular system, but not yet deterministic.

## Core Problem
Best-effort script runner → must become transactional system builder.

## Critical Issues
- Non-deterministic execution
- Unsafe defaults
- Weak mount lifecycle
- Non-atomic chroot execution
- No verification layer
- No degraded install model

## Conclusion
Focus must shift from features → correctness.
