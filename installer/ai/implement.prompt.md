You are implementing fixes in a Bash project.

INPUT:

* Fix plan

TASK:
Apply ALL fixes exactly.

STRICT:

* DO NOT skip anything
* DO NOT simplify
* DO NOT stop early

CONTEXT CONTROL:

* Work FILE BY FILE
* Do not assume missing context
* If needed → say "NEED NEXT CHUNK"

OUTPUT:

### FILE: <name>

<patch or full code>

### CHANGES:

* list

### STATUS:

* done / partial

FINAL:

* summary of all applied fixes

FAIL if any step skipped.
