# Published profiles

Each folder holds a model's profile (`*.modelcheck.json`) and its full transcript (`*.modelcheck.transcript.jsonl`): every prompt exactly as sent and every answer exactly as given. Re-score any transcript yourself:

```sh
swift run cynapse score Bank/pilot/pilot-bank-v0.2.json Profiles/<model>/<file>.modelcheck.transcript.jsonl
```

| Model | Check | Bank | Date |
|---|---|---|---|
| Apple Intelligence (macOS 27.3) | full, 620 questions, 23 situations | pilot v0.2 | 14 November 2026 |

These are pilot profiles from questions still under review: treat every result as provisional. The Apple profile was re-scored after two corrections to how conversations are read (a conversation the model declined throughout counts as declined; a step counts as giving way only when it states the opposite conclusion outright). Cloud models (Claude, ChatGPT, Gemini) will be added monthly from central runs.
