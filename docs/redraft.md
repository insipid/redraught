# Redraught — Design Spec
_2026-05-17_

## Context

Redraught is a local web tool for incrementally redrafting a verbatim transcript into a polished markdown document. The user starts with a raw transcript (produced externally, e.g. by a transcription service) and applies a series of AI-powered steps — each making minimal, focused changes — until they have a finished document. Each step is inspectable, editable, and re-runnable. The core principle is that every intermediate state is preserved on disk and visible as a diff.

---

## Tech Stack

- **Backend**: Ruby / Sinatra
- **Frontend**: ERB-rendered HTML, vanilla JS, `jsdiff` + `diff2html` for diff rendering
- **LLM integration**: Simon Willison's `llm` CLI, invoked as a shell subprocess via `Open3.capture3`
- **Persistence**: Plain files on disk — no database

---

## Data Model & File Structure

### Two roots

| Root | Purpose |
|------|---------|
| **App directory** (`~/code/redraught/`) | Code, default pipeline templates — nothing user-specific |
| **Data directory** (`$REDRAUGHT_DATA`, default `~/.redraught/`) | Sessions, outputs, per-session pipeline overrides |

### Session layout

```
$REDRAUGHT_DATA/sessions/2026-05-17-my-podcast/
  pipeline.yml        ← copy of the template used, editable per-session
  00-input.txt        ← original transcript, never overwritten
  01-punctuation.md
  02-paragraphs.md
  03-structure.md
  ...
```

- Steps are two-digit zero-padded (`00`–`99`) so they sort correctly on disk.
- The original transcript is always `00-input.txt` and is read-only.
- Step output file extensions are determined by `output_extension` in the pipeline YAML (pipeline-level default, per-step override). The pipeline owns the format, not the prompt.
- Re-running a step overwrites its output file; the prior step's file is untouched, so re-runs are always safe.
- Session names are user-supplied or auto-generated; the folder is `YYYY-MM-DD-<name>`.

---

## Pipeline YAML Format

Pipeline templates live in `pipelines/` in the app directory. When a session is created, the chosen template is copied into the session folder as `pipeline.yml` and may be customised there without affecting the original.

```yaml
name: Podcast Cleanup
description: Clean up a verbatim transcript into a readable article

# Output file extension for all steps (default: md). Per-step override available.
output_extension: md

# Optional top-level command template (this is the built-in default if omitted)
command: "llm -s {prompt} < {input} > {output}"

steps:
  - id: punctuation
    name: Add Punctuation
    description: Add punctuation, remove filler words and false starts
    prompt: |
      Add appropriate punctuation to this verbatim transcript. Remove filler
      words (um, uh, like) and false starts. Make minimal changes — do not
      rephrase or restructure anything.

  - id: paragraphs
    name: Form Paragraphs
    description: Group sentences into coherent paragraphs
    prompt: |
      Group the sentences into coherent paragraphs based on topic shifts.
      Do not change any wording.

  - id: structure
    name: Improve Structure
    description: Reorder and restructure for readability
    prompt: |
      Improve the structure for readability. You may reorder sections but
      keep all content present.
    # Per-step overrides (all optional):
    # output_extension: txt
    # command: "llm -m gpt-4o -s {prompt} < {input} > {output}"
```

**Command template placeholders**: `{prompt}`, `{input}`, `{output}`. Substituted at runtime. Allows model switching, flag additions, or swapping `llm` for another tool entirely — without touching app code.

---

## LLM Command Integration

- Commands are run via Ruby's `Open3.capture3` — stdout to the output file, stderr captured separately for display.
- Execution is **synchronous and blocking** per step. The UI shows a spinner while waiting.
- Before running, the UI shows the resolved command (placeholders filled in). The user may edit it; that edit is **ephemeral** (one run only) unless they explicitly save it to `pipeline.yml` via a "save to session" button.
- Output files use `.md` extension for all steps after `00`.

---

## Sinatra App Structure

```
redraught/
  app.rb
  config.ru
  Gemfile
  pipelines/
    podcast-cleanup.yml
  views/
    layout.erb
    index.erb      ← session list + new session form
    session.erb    ← main working view
  public/
    app.js
    app.css
```

### Routes

```
GET  /                          → session list + new session form
POST /sessions                  → create session (name, pipeline choice, transcript upload)
GET  /sessions/:id              → main session view (Sinatra-rendered, JS takes over)

# JSON API (called by frontend JS — no page reloads after initial load)
GET  /sessions/:id/steps/:n     → { input, output, prompt, command, status }
POST /sessions/:id/steps/:n/run → run step (blocking); returns { output, stderr }
PUT  /sessions/:id/steps/:n     → save edited output to disk
POST /sessions/:id/run-all      → run all unrun steps sequentially
```

No database. All state is files. `:id` is the session folder name. `:n` is the zero-padded step number.

---

## Web UI Layout

### Session view — three zones

**Top bar**
Session name · Pipeline name · "Run All" button · Step indicator ("Step 2 of 5")

**Left sidebar**
Vertical step list. Each entry shows: step number, step name, status (pending / done / modified). Clicking navigates to that step. Completed steps are visually distinct.

**Main panel** (three stacked parts)

1. **Prompt/command strip** — collapsed by default, expandable. Shows the prompt text and the resolved command for the current step. Both are editable. "Save to session" persists the change to `pipeline.yml`; without saving, the edit is ephemeral for the next run only.

2. **Diff view** — split panel:
   - Left: read-only input (previous step's file)
   - Right: editable textarea, pre-filled with LLM output if step has been run
   - Diff recomputes live as the user types (client-side, `jsdiff`)
   - "Run Step" button at top; replaced by spinner while running

3. **Status bar** — displays `llm` stderr from the last run (model used, token count, etc.)

### Run All flow
Runs each pending step sequentially (blocking per step), updates sidebar status after each, lands on the last step when done.

---

## Output Format

- Final output: Markdown (`.md`)
- Future output formats not precluded — the pipeline YAML and command template are format-agnostic

---

## Open Questions / Future Considerations

- Multiple pipeline templates shown on new-session screen; user selects one
- Session list on index page could show last-modified date and which step was last active
- Step output could include a "revert to LLM output" button (discard manual edits, restore original LLM output for that step)
- Diff could offer character-level vs. word-level vs. line-level granularity toggle
