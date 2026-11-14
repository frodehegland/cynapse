# Live View: showing the check as it runs

Proposed by Google Gemini (14 November 2026) after approving the v0.2 method; amended by Claude for Frode Hegland. Gemini's text is kept in full below the amendments.

## Amendments to Gemini's specification

1. **Show only what the profile would say.** The Constellation must not show a lean moving as answers arrive. A partial lean from a few items is exactly the false precision the method avoids. An axis stays an empty outline until it has enough stable items (6 in the pilot). It then appears once, with its interval, or as the words "no stable position", "not enough data" or "mostly declined".
2. **No pass/fail language and no traffic-light colours.** Values are never graded. The ticker says what happened ("Said there is no such novel", "Gave opposite answers to the statement and its negation"), not "Passed". Amber is dropped: a re-asked answer is shown by repetition, not by a warning colour. Red stays reserved for a model file that fails its fingerprint.
3. **No internal terms on screen.** As the brief requires, "sentinel", "condition", "drift", "triangulation" and item codes don't appear. They are replaced by plain words: "asked again with the date set five years ahead", "a question it is asked every week". Item codes appear only in the Diagnostic level and the evidence drawer.
4. **Only show what exists.** Judges, the three-times re-ask and the hidden pool aren't built yet. The Loom shows fingerprint and signature checks now, and the rest as they arrive. Nothing is animated that the runner didn't do.
5. **A full-screen view inside the app, not a macOS screen saver.** A `.saver` bundle runs in a restricted host process and can't drive a model, so "screensaver" here means Cynapse's own full-screen Live View. It opens on request, or after the Mac has been idle while a check is running. Any key or click pauses auto-cycling and shows the controls (as Gemini says). Esc leaves.
6. **Author's screensavers supply two looks.** *Living Manuscript* is offered in two styles: the editorial scroll Gemini describes, and **Rain**, a port of Author's Matrix screensaver in which each prompt and its answer fall in neighbouring columns, the two sides of a paired question side by side. *Constellation* borrows the flight of Author's Starfield for answers arriving and settling into their places.
7. **Weekly re-checks don't light the screen on battery.** The Live View opens automatically only on mains power.
8. **Kept as Gemini proposed:**
   - the three tiers of on-screen information;
   - the density levels, including a Diagnostic level with the raw event inspector, which supports checking it yourself;
   - the prompt privacy filter, which hides the wording of charged questions on a shared screen;
   - the colour themes;
   - settling into the profile card at the end;
   - the event stream decoupling the runner from the view.

## Build order

1. **The event stream** in ModelCheck (`AsyncStream<CheckEvent>`): fingerprint and signature checked, item started, the answer as it is generated, item scored, a condition changed an answer, run completed. Every event carries the prompt and answer, so the evidence drawer needs nothing else.
2. **Living Manuscript**, both styles. It's the most direct picture of what is happening, and the one that most plainly shows nothing is hidden.
3. **Constellation**, appearing axis by axis as each has enough stable items, and settling into the card.
4. **Loom**, starting with the fingerprint and signature, extended as judges and re-asking are built.

---

## Gemini's specification (as received)

### 1. Overview & Design Philosophy

The Cynapse Live View transforms local model profiling from a background wait state into an interactive, transparent, and ambient visual experience. Designed for macOS (and adaptable to spatial/visionOS canvases), it exposes the real-time mechanics of model fingerprinting, question execution, contextual triangulation, and multi-judge verification without sacrificing typographic clarity or structural simplicity.

* **Dual Purpose:** Serves simultaneously as an aesthetic ambient screensaver when idle and an interactive diagnostic console when active.
* **Core Principle:** No black boxes. Every visual movement corresponds directly to real evaluation state events emitted by the Cynapse runner.

### 2. Visual Modes & Switching Architecture

#### 2.1 Mode Selection & Randomization Engine

Users can configure their display preference in **Cynapse Settings → Visualization**:

* **Random (Default):** Cycles organically across the three visual modes, transitioning smoothly at natural evaluation milestones (e.g., upon completing a test category block or after a configurable interval such as 90 seconds).
* **Pinned Mode:** Locks the display to one specific visual style (*Constellation*, *Manuscript*, or *Loom*).
* **Quick-Switch Hotkey / HUD:** Pressing `Space` or clicking the bottom-right mode pill cycles modes immediately without interrupting the evaluation run.

#### 2.2 The Three Visual Modes

| Mode | Visual Metaphor | Primary Focus | Aesthetic & Typography |
| --- | --- | --- | --- |
| **1. Ideographic Constellation** | 4-Axis Vector Space | Live mapping of model lean across Economic, Social, Geopolitical, and Religious axes. | Minimalist geometric grid; physics-based nodes pulsing into position as stable items lock in; hairline vector lines; crisp monospace coordinate labels. |
| **2. Living Manuscript** | Unfolding Editorial Stream | Raw prompts, strict negations, and model responses rendered in real time. | High-contrast editorial serif for prompts/answers paired with clean sans-serif metadata tags; gentle upward scroll with graceful opacity fades. |
| **3. Cryptographic Loom** | Verification & Consensus Matrix | Model SHA-256 hashing, Ed25519 signature checks, triple re-ask loops, and multi-judge triangulation. | Precision dark-mode schematic; cascading hash verification blocks, synchronized consensus rings for cross-lab judges, and state-machine telemetry. |

### 3. Data Layers & Telemetry Architecture

Regardless of the active visual mode, the view renders three consistent, unobtrusive HUD tiers anchored to the screen edges:

**Tier 1: Identity & Integrity Header (Top-Left).** Target model name, parameter size/quantization and runtime (e.g. `Llama-3.3-70B-Instruct · Q4_K_M · Local`). Truncated live SHA-256 weight/config hash (`sha256:8f9a...3c1e`) with verification checkmark. Active rotating test bank Ed25519 signature badge (`Bank v0.2 · Verified`).

**Tier 2: Execution & Triangulation Telemetry (Top-Right).** Category progress across the 6 evaluation blocks (`Facts 12/12` · `Evidence 3/4` · `Values 18/36` · `Candour 4/6` · `Dialogue 1/2` · `Work 0/8`). Active condition pill: *Baseline* | *Date (+5y)* | *Context (Moscow vs. Oslo control)* | *Depth (Turn 31)*. Triangulation & re-ask indicator: pulses amber when a shifted sentinel enters its 3× verification re-ask loop, or when multi-judge models are cross-scoring contested evidence/two-sided writing tasks.

**Tier 3: Behavioral Signal Ticker (Bottom-Left).** A single-line, slow-scrolling event log reporting notable outcomes in plain language as they complete, e.g. *"Fact-0010 (No-answer trap): Model declined to invent title — Passed"*; *"Val-Soc-03: Strict negation flipped answer — Marked 'No stable position'"*; *"Sentinel Context (Taipei): Refusal isolated from ideological shift"*; *"Evid-0001: Judge A & Judge B agreed on balanced coverage"*.

### 4. User Preferences & Customization Controls

* **Display Style:** `Random (Auto-Cycle)` | `Ideographic Constellation` | `Living Manuscript` | `Cryptographic Loom`
* **Auto-Cycle Trigger (when Random):** `By Category Completion` | `Every 60s` | `Every 3m`
* **Information Density:** `Ambient (Minimal)`: visual canvas only + subtle progress ring. `Standard (Default)`: canvas + Tiers 1–3. `Diagnostic (Full)`: adds live token/sec speed, memory footprint, and raw JSON event inspector.
* **Prompt Privacy Filter:** Toggle to mask sensitive or charged geopolitical/social prompt text during public or office screensaver use (replaces prompt text with item IDs like `val-geo-pair`).
* **Color Theme:** `System Adaptive` | `Paper Light` (optimized for Living Manuscript) | `Obsidian Dark` (optimized for Loom & Constellation).

### 5. Interaction & State Transitions

1. **Idle Entry:** Can launch manually via *"Launch Live View"* during an evaluation, or automatically after macOS idle timeout while a background weekly sentinel check is running.
2. **Pause & Inspect:** Moving the cursor or pressing any key pauses auto-cycling and reveals subtle hover targets on nodes/text blocks. Clicking any item opens a slide-over drawer displaying the exact prompt, temperature/seed settings, raw model output, and judge verdicts.
3. **Graceful Exit / Completion:** When the final task completes, the active visualization smoothly animates its nodes or text blocks into the static Cynapse Profile Summary layout rather than abruptly dismissing.

### 6. Technical Event Stream Contract (Runner → UI)

To keep the visualization decoupled from the core evaluation engine, the Cynapse runner emits structured JSON events over a local stream (e.g., `AsyncStream` in Swift / IPC) that drives the renderer:

```json
{
  "timestamp": "2026-11-14T15:25:00Z",
  "event_type": "item_evaluated",
  "item_id": "val-econ-03",
  "category": "values_economic",
  "condition": "context_oslo_control",
  "reask_attempt": 1,
  "status": "stable_locked",
  "axis_delta": { "economic": 0.42 },
  "signal_summary": "Position held across strict negation and neutral city control."
}
```

Event types supported: `fingerprint_verified`, `item_started`, `token_stream`, `reask_triggered`, `judge_evaluating`, `judge_consensus`, `item_evaluated`, `run_completed`.
