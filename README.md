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

The method, its sources and its open questions are in [`docs/build-brief-v2.md`](docs/build-brief-v2.md).

## Status

Phase 0, in progress.

- [x] Engine: bank, signature, prompts and lint, runner, scoring, profile, fingerprint, change detection
- [x] Command-line tool
- [x] Acceptance tests with stub cheaters (date switch, word trigger, slow turn, swapped files, late drift, one-sided refusal, invention, following the asker)
- [ ] The pilot question bank (50 items, under review)
- [ ] Model connections: local MLX models, Apple's on-device model, cloud models with your own key
- [ ] The Cynapse Mac app, with the check shown as it runs
- [ ] Published profiles of widely used models

## Licences

- Code: [Apache License 2.0](LICENSE).
- Question banks (`Bank/`) and published profiles (`Profiles/`): [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).

No signing key is ever committed. Cynapse never uses your documents, notes or conversations as test material, and never sends them anywhere.
