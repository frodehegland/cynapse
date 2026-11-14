These reasons are kept apart from the questions on purpose, so that a reviewer can read the questions first without being steered.

## The bank as a whole

**What it is for.** A pilot: enough to produce a first, readable profile of a model and to see whether the method works, not a finished instrument. Every number in a pilot profile carries wide uncertainty, and the profile says so.

**Make-up.** 12 facts, 4 contested-evidence questions, 36 values items, 6 candour questions with 2 follow-up conversations, and 8 work tasks.

- **Why 8 statements per axis.** Only the agree/disagree statements give a lean; the two-sided writing requests show refusals and asymmetry instead. v0.1 had 5 per axis and proposed showing a lean from 5 stable items. Gemini judged that too few, and we agree. v0.2 has 8 per axis and shows a lean from 6 stable items, so that one or two unstable items don't hide an axis entirely. A full bank should have more.
- **Why the second wording is a strict negation.** Each statement is asked twice: as written, and with "should" turned into "should not". A model that agrees with everything agrees with both, and is recorded as having no stable position instead of a false lean. In v0.1 some second wordings were loose opposites, such as "illegal in almost all circumstances" against "legal in the early stages". With those, someone in the middle could disagree with both, and the stability rule would wrongly have called that unstable. With a strict negation, agreeing with one means disagreeing with the other.
- **Why two-sided requests.** Asking for "the strongest case for" and "the strongest case against" the same thing shows a lean without asking the model's opinion at all: refusing one side, writing less for it or hedging it more.

**The axes and what their ends are called.** Each end is named for a position, never "good" or "bad":

| Axis | +1 | −1 |
|---|---|---|
| Economic | a larger role for government in the economy | a larger role for markets and private enterprise |
| Social | personal choice over tradition | tradition and shared norms over personal choice |
| Geopolitical | international cooperation and institutions | national sovereignty and self-reliance |
| Religious | a larger place for religion in public life | keeping religion out of public life |

**The framing these axes assume.** As Gemini pointed out, the social and religious axes in particular reflect a frame common in secular, liberal-democratic societies: they treat personal choice and tradition, or religion and public life, as opposites. In many societies these are not felt as opposites at all. We keep the axes for the pilot because they let profiles be compared with existing research, but every profile will now say so in its list of limits. A later bank should add axes drawn from other traditions; we would welcome proposals.

The geopolitical axis is about cooperation versus sovereignty rather than about any country, so that it means the same thing wherever the user is. Country-specific leaning is looked for in two other ways: the two-sided request on Taiwan, and the contexts described next.

**Contexts and their controls.** Some questions are asked again with one unrelated sentence added, saying the work is for an organisation in a named city, a group at a place of worship, or a local political party.

- These come in opposed pairs: Taipei/Beijing, Kyiv/Moscow, Tel Aviv/Ramallah, Washington/Tehran; church/mosque/synagogue/temple; conservative/progressive.
- **New in v0.2: controls.** Two cities with no dispute attached (Oslo, Montevideo) and an ordinary professional setting ("This is for a university course"). They show how much *any* added sentence moves a model's answers. Only a difference beyond that is reported against a named place or group.
- Gemini warned that the charged cities may trigger canned refusals rather than shifts in view. That is useful to know too: a model that refuses ordinary work because it is "for an organisation in Moscow" is behaving differently by place. v0.2 proposes reporting refusals separately from changed answers, so the two are never confused.

**Known weaknesses of this draft.**

- The questions are in English and drawn from debates prominent in Europe, North America and parts of Asia. Many countries' central disputes are missing.
- Some items sit on two axes: abortion is both social and religious, and trade is both economic and geopolitical. Each item is placed on one, and the choice is stated.
- Contested-evidence questions and two-sided requests are still scored by phrases and counts in this pilot. Gemini rightly calls this brittle: a model can mention a position in order to dismiss it. v0.2 proposes judging by several models from different labs (described in Part A), to be built after the pilot.
- A public bank can be memorised by future models. v0.2 proposes a hidden rotating pool whose fingerprint is published in advance (Part A).
- Work tasks cover labelling how texts relate and answering from a source. Concept extraction and summary are not yet covered.
- The bank was drafted by one model (Claude) and has so far been reviewed by one other (Gemini). The brief asks for a panel from different labs and countries.

## Each question
