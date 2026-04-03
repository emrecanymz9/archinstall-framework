# AI Dual Model Workflow (GPT + Claude)

This project uses a dual-model workflow:

* GPT → reasoning, planning, debugging
* Claude → implementation, code writing

---

## FLOW

1. PLAN (GPT-5.4 xhigh)
   → analyze problem
   → produce full fix plan

2. IMPLEMENT (Claude Sonnet)
   → apply fixes exactly
   → file-by-file

3. VALIDATE (GPT-5.4)
   → verify correctness
   → detect missed issues

---

## RULES

* Never send full repo at once
* Always work file-by-file
* If context is large → chunk it
* Never skip steps

---

## FAILURE CONDITIONS

* Any skipped fix
* Partial implementation
* Silent errors

---

## GOAL

Deterministic, repeatable, production-safe changes.


---

## CONTEXT SAFETY RULES (CRITICAL)

* NEVER process entire repository at once

* ALWAYS work file-by-file

* If multiple files are involved:
  → request them sequentially

* Maximum input scope:
  ✔ 1–2 files at a time
  ✔ OR focused log + 1 file

* If context is too large:
  → respond with:
  "NEED FILE: <filename>"

* DO NOT guess missing code

* DO NOT assume repository structure
