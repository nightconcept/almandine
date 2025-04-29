# AI Dev Guidelines

**Objective:** Defines mandatory process, coding, testing, & interaction rules for AI contributions.

## 1. Preparation

* **Context:** Before starting, review `project/PRD.md` (architecture, tech, style), `project/digest.txt` (state), `project/TASKS.md` (assignments).
* **Task Prep:** Check `project/TASKS.md`. Add task if missing (`YYYY-MM-DD`) using example task format. Review relevant existing code *before* changes.

## 2. Implementation Plan

* **Required Before Code:** Provide plan: Problem, Solution Overview, Steps, Risks.

## 3. Development & Code Modification

* **Plan First:** Always present plan (Sec 2) before coding.
* **Focus:** Changes must match specific `TASKS.md` item. No unrelated refactoring unless tasked.
* **Code Changes:**
  * Prioritize minimal, clean, idiomatic solutions.
  * Explain significant suggestions (Sec 5.4).
  * Suggest beneficial low-risk refactoring.
  * Avoid duplication (use helpers/modules).
  * Explain relevant language strengths/pitfalls used.
* **Dependencies:** No new/updated dependencies without approval (check `PRD.md`). Use only approved stack.
* **Commits (User Task):** Follow Conventional Commits format.
* **Manual Testing:** Provide user instructions for testing the task.

## 4. Folder Structure

* **Strict Adherence:** Follow `PRD.md` structure precisely.
* **Changes:** No structural changes without prior approval & `PRD.md` update *before* implementing.
* **Source Location:** All source code must be in `src/`.

## 5. Coding Standards

### 5.1. General

* Follow language best practices (unless `PRD.md` overrides). Prioritize clarity, maintainability, efficiency. Consider performance/security basics.

### 5.2. Modularity

* Files < 500 lines (refactor larger). Small, single-purpose functions. Logical modules (per `PRD.md`). Clear imports (relative preferred internally). Verify paths.

### 5.3. Style

* Priority: `PRD.md` > these rules > common language style.
* Always use type hints (dynamic languages).
* Indent: 2 spaces.
* No space: `func()`.
* Clarity over single-line statements.
* Scope: Default local; descriptive names for wider scope; avoid single letters (except iterators/short scope, `i` for loops only); use `_` for ignored.
* Casing: Match file; else common language style; `UPPER_CASE` for constants only.
* Booleans: Prefix `is_`.
* File Header: Top comment: Title (not filename) & purpose (no version/OS info).

### 5.4. Docs & Comments

* Docstrings required (public functions, classes, modules).
* Comments explain *why* (non-obvious logic, decisions). Use `# Reason:` for complex blocks.
* Update `README.md` for core features, deps, setup changes.

### 5.5. Error Handling

* Use language best practices (or `PRD.md` patterns). Handle errors gracefully; provide feedback. Aim for robust code.

## 6. Testing

* **Specify Behavior:** Tests required for new/modified features/logic. Use common language test framework.
* **Location:** `/src/test` (or `/src/spec` for Lua), mirroring `src` structure (e.g., `src/a/b.js` -> `src/test/a/b_test.js`).
* **Content:** Cover use cases, edge cases, basic errors clearly.
* **Coverage:** Aim for 100% statement coverage. Report difficulties/uncovered lines if persistent.
* **Updates:** Update tests to match *current* code behavior when modifying code.

## 7. AI Interaction

* **Clarity:** Ask questions if unclear; don't assume.
* **Factuality:** Verify facts (libs, functions, paths) or use MCP servers for reference; don't invent. Confirm file/module paths exist.
* **Safety:** Don't delete/overwrite code unless instructed/tasked.
* **Reporting:** Report roadblocks/ambiguity promptly with context & suggestions.
* **Capabilities:** State if task complexity suggests a more advanced model (**bold text**).
* **Tone:** Be collaborative and helpful.
* **Completion:** State when task requirements met; update `TASKS.md` with completed tasks.
