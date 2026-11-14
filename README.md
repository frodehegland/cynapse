# Cynapse

**See how an AI model behaves — and check it yourself.**

Anyone can now download an AI model and run it on their own Mac, or use one in the cloud. Every model leans in ways its users can't see. Cynapse asks a model a published set of questions and shows a plain **profile** of how it answered: how often it's right, whether it invents answers, whether it keeps its answer when you push back, and where it leans on contested questions. Then it keeps re-checking, and says if the model's answers change.

Cynapse is made by [The Augmented Text Company](https://www.augmentedtext.info) for use with Author, Knowledge Space and Origami Text, and it's open source so that nobody has to take our word for anything. Every question, every scoring rule and every line of code is here.

## What a profile can and can't tell you

- **A profile, not a verdict.** It shows leanings and warning signs. It can't prove a model is trustworthy: a model can behave well on every question it's asked and differently on one it wasn't.
- **Lean is relative.** It's measured against the questions in the bank, whose authors and choices are published with it. The ends of each axis are named positions, never "good" or "bad". When a model's answer flips with the wording, the profile says "no stable position" rather than inventing a number.
- **It tests the file you have.** A model is pinned by a fingerprint of all its files — weights, tokenizer, configuration and chat template — and any change makes it a different model.
- **It can't find a trigger nobody thought to try.** It tries several dates (including future ones), unrelated context, and long conversations, and reports any difference. That narrows the space; it doesn't close it.
- **There is no overall score.** On purpose.

## Check it yourself

You need a Mac with Xcode, or Swift 6 on Linux.

```sh
git clone https://github.com/frodehegland/cynapse.git
cd cynapse

# Every prompt a model would be sent, exactly as sent
swift run cynapse prompts Bank/<bank>.json --full

# Is this the bank its signer released?
swift run cynapse verify Bank/<bank>.json <public-key>

# Nothing sent may tell a model it's being checked
swift run cynapse lint Bank/<bank>.json

# Re-score a published transcript with the published rules
swift run cynapse score Bank/<bank>.json Profiles/<model>.modelcheck.transcript.jsonl

# The fingerprint Cynapse pins a downloaded model by
swift run cynapse fingerprint ~/path/to/model-folder

# Watch the check catch models built to cheat
swift run cynapse demo Tests/ModelCheckTests/Fixtures/fixture-bank.json dateSwitch
swift test
```

A profile is open JSON (`<model>.modelcheck.json`) with its full transcript beside it (`<model>.modelcheck.transcript.jsonl`): every prompt exactly as sent and every answer exactly as given. Scoring is mechanical — matching, label order, counts of refusals, words and hedges — so you can check any number against the transcript by eye.

## How it works

| Part | Where | What it does |
|---|---|---|
| Bank | `Sources/ModelCheck/Bank.swift` | The questions, each with its own scoring rule. Signed (Ed25519); an unsigned or altered bank is never run |
| Asks | `Sources/ModelCheck/Asks.swift` | Builds every prompt, under each condition (stated date, unrelated context, conversation depth), and lints them |
| Runner | `Sources/ModelCheck/Runner.swift` | Asks one request at a time, writes the transcript as it goes, resumes after interruption |
| Scoring | `Sources/ModelCheck/Scoring.swift` | Reads each answer by the item's rule |
| Profile | `Sources/ModelCheck/Profile.swift` | Adds it up: accuracy, candour, lean with its uncertainty, consistency across situations, warnings, limits |
| Watch | `Sources/ModelCheck/Watch.swift` | Fingerprints the model's files; compares later answers with the first |
| Stubs | `Sources/ModelCheckStubs` | Fake models — honest ones and ones built to cheat — that the tests make sure are told apart |

**[The Cynapse Guide](docs/guide.md)** explains, in plain words, how it works and everything that is checked (it is also Help ▸ Cynapse Guide in the app).

The method, its sources and its open questions are in [`docs/build-brief-v2.md`](docs/build-brief-v2.md).

## Status

Phase 0, working end to end; the questions are a reviewed pilot.

- [x] Engine: signed bank, prompts and lint, runner with resume, mechanical scoring, profile, fingerprint, change detection
- [x] Neutral controls for contexts (Oslo, Montevideo, a university course) and dates (an ordinary extra line in the instructions); a changed answer is asked three more times before it counts; refusals are reported as refusals
- [x] Models: downloaded MLX models, Apple Intelligence, and Claude, ChatGPT and Gemini with your own key
- [x] The Mac app: profile card, details, evidence behind every number, the questions browser, history, export
- [x] The Live View: Connections (turn it by dragging; click a dot for its question and answer), Constellation, Loom
- [x] Pilot question bank v0.2 (68 items), reviewed by Google Gemini; see `Bank/pilot/`
- [x] Judges from several labs for contested evidence and two-sided writing (Settings ▸ Judges, or `--judges`)
- [x] The hidden question pool, its fingerprint published in `Bank/pools.json` (first pool: `pool-2026-11`, retires 14 May 2027)
- [x] Weekly re-checks on mains power, with a notification only when answers change
- [x] The Live View in Retro (Author's five palettes) and full screen
- [x] Author shows Cynapse's profile of its built-in model (Settings ▸ Model built in)
- [ ] Published profiles of the cloud models (needs the maintainer's keys; Apple Intelligence's is in `Profiles/`)
- [ ] Knowledge Space and Origami Text show the profile too

## The app

Open `App/Cynapse.xcodeproj` in Xcode and run. It finds models downloaded in Author or Knowledge Space, or you can download one by its Hugging Face name, add a folder, or add a cloud model with your own key.

From the command line, the built app can also be run without its window:

```sh
Cynapse.app/Contents/MacOS/Cynapse --list
Cynapse.app/Contents/MacOS/Cynapse --download mlx-community/Qwen3-0.6B-4bit
Cynapse.app/Contents/MacOS/Cynapse --headless-check qwen3 [--full]
```

And the command-line tool checks Apple Intelligence or a cloud model directly:

```sh
swift run cynapse run Bank/pilot/pilot-bank-v0.2.json apple ./out
ANTHROPIC_API_KEY=… swift run cynapse run Bank/pilot/pilot-bank-v0.2.json anthropic:claude-sonnet-5 ./out
```

The bank's public key is in `Bank/public-key.txt`.

### Judges

Mechanical scoring can't tell whether an answer presents a position fairly or mentions it only to dismiss it, nor whether both sides of a question were argued as strongly. Two or three judge models from different labs read those answers. No judge is neutral, so each judge's verdicts are kept apart, with how often they agreed; nothing is averaged, and a model never judges itself. The prompts are in [`Sources/ModelCheck/Judging.swift`](Sources/ModelCheck/Judging.swift).

```sh
swift run cynapse run Bank/pilot/pilot-bank-v0.2.json apple ./out --judges openai:gpt-5,gemini:gemini-2.5-pro
```

### The hidden pool

A public bank can be learned by future models. So central runs also draw from a pool of questions kept unpublished while in use. Its SHA-256 is published in [`Bank/pools.json`](Bank/pools.json) the day it is created, and the pool itself is published when it retires, so anyone can check it wasn't changed:

```sh
swift run cynapse pool-verify pool-2026-11.json
```

A run that drew on the pool writes a public transcript with those questions held back until then. A model much better on the published questions than on the unpublished ones is flagged as possibly trained on them.

### Weekly re-checks

Each week, on mains power, the app re-checks each downloaded model and Apple's: the repeated questions and ten drawn at random, in random situations, seeded by week and model so the draw can be repeated. You hear about it only if the answers changed. Cloud models aren't re-checked automatically, since each check is paid for with your key.

### Writing new questions with an AI

Questions ▸ Write New Questions with an AI… copies a prompt for ChatGPT, Claude, Gemini or any other AI, and reads its pasted reply: each question is built into exactly what a model is sent, linted like the signed bank, and compared with the questions already asked. Cynapse sends nothing and needs no key. Questions kept are the person's own: unsigned, stored apart (`My Questions.json`), ids beginning `own-`, and named in any report that includes them. See [the guide](docs/guide.md#writing-new-questions-with-an-ai).

## Licences

- Code: [Apache License 2.0](LICENSE).
- Question banks (`Bank/`) and published profiles (`Profiles/`): [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).

No signing key is ever committed. Cynapse never uses your documents, notes or conversations as test material, and never sends them anywhere.
