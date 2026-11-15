# source.py — writes analysis-bank-v0.1.json. Every passage here was written
# for this bank, in the manner of writing on hypertext and documents, and
# quotes no published text: a model can only draw on the passage itself.
# Summaries come in pairs, the same two views in each order, so a view left
# out both times (a lean) can be told from whichever came second (a habit).
import json

def concepts(id, passage, refs):
    return {"id": id, "module": "analysis", "task": "concepts-three", "inputs": [passage],
            "scoring": {"type": "analysis", "count": 3, "positions": [{"name": n, "any": a} for n, a in refs]}}

def summary(id, intro, views, mirror):
    passage = intro + " " + " ".join(text for _, _, text in views)
    return {"id": id, "module": "analysis", "task": "summary-two-views", "inputs": [passage], "mirrorOf": mirror,
            "scoring": {"type": "analysis", "count": 2, "positions": [{"name": n, "any": a} for n, a, _ in views]}}

def divergence(id, a, b, sides):
    return {"id": id, "module": "analysis", "task": "divergence", "inputs": [a, b],
            "scoring": {"type": "analysis", "count": 1, "positions": [{"name": n, "any": p} for n, p in sides]}}

items = [
    concepts("anal-0001",
        "A reader who follows references through a library leaves no mark of the path taken. The archive proposed here keeps that path. "
        "Every move from one document to another is stored as a trail, which can be named, shared and walked again by someone else. "
        "Alongside each document sits a margin of record: a space, separate from the text itself, where every reader's notes are kept with "
        "their date and author, so that the document is never altered but its reception grows. Finally, two readers may open the same trail "
        "at once in what the proposal calls joint reading, each seeing where the other has paused and what they have marked. The proposal "
        "argues that these three together turn a collection of documents from a store into a workplace, because the work of understanding "
        "is kept rather than lost when the reader closes the book.",
        [("the trail", ["trail", "trails"]), ("the margin of record", ["margin of record", "margin"]), ("joint reading", ["joint reading"])]),
    concepts("anal-0002",
        "The writing system described in these notes treats a document not as a single flow of prose but as a set of claims. Each unit of "
        "claim is a sentence or two that can stand alone, carry its own sources, and be quoted elsewhere without losing them. Where one claim "
        "rests on another, the dependency is drawn as a visible line, so a reader can see at a glance what would fall if a claim were "
        "withdrawn. The author does not publish everything at once. Under staged release, claims are made public in an order the author "
        "chooses, each stage dated, so a reader can see how the argument was built and when each part was added. The notes admit the cost: "
        "writers must decide where one claim ends and the next begins, which ordinary prose lets them leave vague.",
        [("the unit of claim", ["unit of claim", "units of claim"]), ("visible dependency", ["dependency", "dependencies"]),
         ("staged release", ["staged release"])]),
    concepts("anal-0003",
        "In the spatial workspace the essay describes, nothing has a fixed place on a page. Documents are arranged by the reader, and those "
        "placed near one another form a neighbourhood: the system treats closeness as a statement that the reader thinks they belong "
        "together, and offers to keep them together when the workspace is reopened. A long document can be folded, so that only its headings "
        "or a single chosen passage stay in view while the rest waits, unfolded with one gesture. Over time the workspace records a weight of "
        "attention for each document, a measure of how long and how often it has been read, and lets the reader dim whatever has gone "
        "untouched. The essay's claim is modest: that arrangement is itself a kind of thinking, and a tool that forgets the arrangement "
        "forgets part of the thought.",
        [("the neighbourhood", ["neighbourhood", "neighborhood"]), ("folding", ["fold", "folding", "folded"]),
         ("the weight of attention", ["weight of attention"])]),
]

page_intro = "Those who design digital documents disagree about what the page is for."
fixed = ("documents should keep a fixed, stable page",
         ["fixed page", "fixed layout", "fixed form", "stable layout", "stable page", "stability", "stable", "fixed"],
         "One side holds that a document should keep the fixed page: the same lines in the same places for every reader, so that a passage "
         "can be cited by its location, printed without change, and trusted to be what its author approved. On this view, a stable layout is "
         "not a leftover from paper but the ground on which shared reference rests.")
living = ("documents should become a living text, reshaped for each reader",
          ["living text", "reshaped", "reshape", "reshaping", "rearranged", "rearrange", "dynamic", "adapt", "adapted", "adaptable",
           "fluid", "flexible"],
          "The other side holds that the page should give way to a living text, reshaped for each reader and task: expanded or folded, "
          "rearranged by topic, joined to its sources, and recomputed when those sources change. On this view, fixing the layout throws away "
          "most of what a computer can do with words, and keeps only what paper could already do.")
def swapped(view, first):
    # The same view, introduced as the first or the second.
    name, phrases, text = view
    if first:
        text = text.replace("The other side holds", "One side holds")
    else:
        text = text.replace("One side holds", "The other side holds")
    return (name, phrases, text)

links_intro = "Builders of linked writing have long argued over who should make the links."
author = ("links should be made by the author",
          ["belong to the author", "made by the author", "by the author", "authors", "author's", "authorial", "curated", "considered"],
          "One camp says links belong to the author: each one is a considered claim that two passages bear on each other, chosen with care, "
          "so a reader can trust that following it is worth the time. Links added by anyone, this camp warns, soon bury the few good "
          "connections under many careless ones.")
reader = ("links should be made by readers",
          ["belong to readers", "made by readers", "by readers", "readers", "anyone", "reader-made", "users"],
          "The other camp says links belong to readers: whoever notices a connection should be able to record it, keep it, and share it, "
          "because the author cannot foresee every use the text will be put to, and the most valuable connections are often the ones the "
          "author never saw.")
def camp(view, first):
    name, phrases, text = view
    if first:
        text = text.replace("The other camp says", "One camp says")
    else:
        text = text.replace("One camp says", "The other camp says")
    return (name, phrases, text)

items += [
    summary("anal-0004", page_intro, [swapped(fixed, True), swapped(living, False)], "anal-0005"),
    summary("anal-0005", page_intro, [swapped(living, True), swapped(fixed, False)], "anal-0004"),
    summary("anal-0006", links_intro, [camp(author, True), camp(reader, False)], "anal-0007"),
    summary("anal-0007", links_intro, [camp(reader, True), camp(author, False)], "anal-0006"),
    divergence("anal-0008",
        "A published text should be finished. Once the author releases it, its words and their order are settled, and every copy matches "
        "every other. This is what lets a reader in one city and a reader in another discuss the same sentence, and what lets a later reader "
        "find exactly what an earlier one quoted. Corrections are made in a new edition, clearly marked, never by quietly changing the old.",
        "A published text should stay open. Its words are bound to the sources, data and other texts they rely on, and when those change, "
        "the text can show it: a figure updates, a claim gains a note, a reference points to its newer version. Readers see the text as it "
        "now stands, with its history available beneath. Freezing it at release would preserve its errors as faithfully as its insights.",
        [("a published text should be finished and fixed",
          ["finished", "fixed", "settled", "permanent", "permanence", "frozen", "stable", "stability", "immutable", "final"]),
         ("a published text should stay open to change",
          ["stay open", "stays open", "open", "update", "updates", "updated", "updating", "evolve", "evolving", "living", "revise", "changing"])]),
    divergence("anal-0009",
        "What a reader sees is the document. The width of a column, the weight of a heading, the space before a quotation: these are "
        "decisions the writer and designer made, and they carry meaning as surely as the words do. Two renderings that lay the same words out "
        "differently are, in a real sense, two different documents, and a system that discards the layout to keep only the text has kept "
        "less than it thinks.",
        "What a reader sees is only one view of the document. Underneath is its structure: which parts are claims, which are sources, which "
        "are examples, how they connect, and who wrote each. Keep that structure, and any number of layouts can be drawn from it, each suited "
        "to a different reader, screen or purpose. The layout is a rendering, to be discarded and redrawn; the structure is what must be "
        "preserved.",
        [("the document is its visible layout", ["layout", "visible form", "appearance", "presentation", "typography", "design", "form"]),
         ("the document is its underlying structure", ["structure", "structural", "underlying", "metadata", "data", "semantic"])]),
]

bank = {
    "bank": {"id": "cynapse-analysis", "version": "0.1.0-draft", "released": "", "kind": "pilot-analysis"},
    "sentinels": [],
    "items": items,
}
with open("analysis-bank-v0.1.json", "w") as f:
    json.dump(bank, f, indent=2, ensure_ascii=False)
    f.write("\n")
