---
name: bridge
description: Show the user something that is easier to look at than to read, in a native window next to their terminal, and get their answer back as JSON. Use when they say "show me", "give me something visual", "I'll have to see it", "make a prototype", "visual diff", "explain that visually", "let me point at it", whenever you write a draft they will paste somewhere (a mail, message, commit text), whether they asked for it or a skill produced it, when you want to show a plan, a decision with evidence, screenshots, a before/after, a live site with controls or evidence around it, or a set of controls to tune, and whenever you are about to ask a multiple-choice question they cannot answer well from a terminal. Not for a site they can open in their own browser: that is a link in your reply. Never use pbcopy to hand over text; use a Bridge page with a Copy button.
---

# Bridge

You write one file. A window opens next to the user's terminal. They look,
click, drag, point at a spot and type a note. `bridge --read` hands all of it
back to you as JSON. They stay where they are, and you get their answer instead of guessing.

```sh
bridge --lint decision.html   # before presenting: what the page gets wrong, one line each, and what to do instead
bridge decision.html          # present (also .md, .jsx, or a URL)
bridge --read decision.html   # what they answered so far, JSON, returns at once
```

Lint while you still hold the file. It knows the kit's real vocabulary and
says what a guessed class should have been, names a class the page and the
kit both style, flags a colour or radius written out where a `--bridge-*`
token exists, a `pre` that is really a table, and text walls. Errors exit 1; fix them
before they see the page. Warnings exit 0; read them.

## Pages are for eyes

The user wants to see the thing itself, not read about it. Words on a page
only name what they look at or tell them what to do; the meaning is in what
they see and touch.

Every page:

- Show the thing, not a description of it: the mockup, the real screenshot,
  a swatch, a diff, a chart (pages.md "Screenshots", "Swatches", "Evidence:
  code, diffs, bars").
- Numbers live in the picture: bars, labelled axes, a readout next to what it
  measures. Not in sentences.
- More than one part: numbered steps, each a heading, one line that starts
  with a verb ("Drag the pins", "Pick one"), then the visual.
- Give it five seconds before presenting: could they answer without reading
  a paragraph? A page that is mostly prose belongs in your reply or a `.md`.

When it fits:

- Explaining how something works: run the real code on the page, let them
  drag, pull or scrub it, and slow down what is too fast to see (one frame,
  one cycle).
- Choosing: options side by side at the same scale, one short line each, the
  rest of the card is evidence (pages.md "Decision").
- Tuning: one control drives everything on the page, the real site in a
  frame included (pages.md "Controls that drive the preview").

## When to use it, and when not

Use a bridge when the thing is easier to look at than to read, or the answer is
easier to click than to type: a decision with real evidence, a rendered plan, a
draft they will paste, screenshots, a before/after, a live site with something
around it, a handful of values to tune, or anything they should point at.

Do not use it for a one-line question, for a yes/no you can ask in the terminal,
or for things they asked you to just go and do. A window they have to close
is worse than a sentence. And never put three bare labels in a window: that is the
terminal question with extra steps. Options must carry evidence they cannot get
from a terminal (a rendering, numbers, a screenshot, a diff).

A site the user can open themselves is a link, not a bridge. A window that is
nothing but a local dev URL such as `localhost:3000` in a frame is their browser with extra steps; put
the URL in your reply. A site belongs in Bridge only when the window adds something their
browser cannot: they should pin spots on it, controls drive it, it sits next to
evidence (a before/after, a screenshot, a diff), or there is a question about
it on the same page.

## Which medium for what

| The user needs to | Write | Notes |
| --- | --- | --- |
| Read a plan or a summary | `plan.md` | Rendered as it is, patched in place when you rewrite it. |
| Paste a draft (mail, message, commit text) | `reply.txt` | Shown readably with a word count and a Copy button that yields the file byte for byte. Never `pbcopy`. For a draft with options around it, `draft.html` with `data-copy` (pages.md "Draft"). |
| Look at one picture | `shot.png` (also jpg, gif, webp, heic, tiff, bmp) | Shown at a sensible size; they can point at any spot, the note carries the coordinate. |
| Read a PDF | `spec.pdf` | Scrollable. No pins. |
| See a diagram | `diagram.svg` | Rendered inline as a document that scales; they can pin its elements. |
| Look at several things | `bridge a.html b.png c.txt` | All arrive in their list, the first is selected. |
| Choose between things | `decision.html` with option cards | Each option carries evidence. See pages.md "Decision". |
| Tune values | `.jsx` with Mantine controls, or `.html` with inputs | Read the numbers back with `--read`. |
| Just look at a site | Nothing: the URL in your reply | The user has a browser. |
| Point at, tune or judge a live site | An `<iframe>` in a page next to your evidence, controls or question; `bridge http://site.test/page` only when they should pin spots on it | See pages.md "Live site next to evidence". |
| Compare screenshots | `.html` with `.shots` grid or `.wipe` | Absolute paths for local images. They can point at any spot. |
| Anything with tabs, tables, comboboxes, date pickers | `.jsx` | Mantine, one file. See mantine.md. |

Read `pages.md` for plain pages and `mantine.md` for Mantine pages before
writing one. Both have copy-pasteable shapes and the component cheat sheet; the
cheat sheet is verified, your memory of the APIs is not.

## Getting the answer back

**You do not wait.** Present, carry on with whatever else there is to do, and
end your turn as usual. When the user presses Send (or closes the window), the
session that presented the page is woken with the answer: a message beginning
"Bridge: The user answered …" arrives with the answers inline. Then read the
full answer if you need the notes or the git context (`ground`), act on it,
then `bridge --cross` it (see Ending a bridge).

Read at any time to see what they have clicked so far:

```sh
bridge --read page.html
```

```json
{ "status": "open", "version": 1, "answers": { "layout": "grid", "radius": 12 },
  "comments": [ { "id": "3f9a1c2b", "text": "too heavy at phone width", "target": "a.link \"Link text\"",
                  "state": "open", "said": [ { "by": "agent", "at": "…", "text": "…" } ] } ],
  "ground": { "repo": "…", "branch": "main", "commit": "cfa73c0", "headMoved": 0 } }
```

- `status` is `open` (not sent yet), `sent` (they pressed Send), or `closed` (they
  closed the window without answering: that means **no, or not now**; do not
  present it again unchanged).
- `answers` is what they have clicked or typed so far, keyed by `data-record`
  (or recorded by the page's own script through `bridge.set`; see
  [pages.md](pages.md)). Answers before Send are real and you may act on them.
- `headMoved` counts commits since they answered. If it is large, re-read the
  answer with that in mind.
- Only the session that presented a bridge gets its answers. Another session
  sees `heldBy` instead. Presenting the file again takes it over.

`--wait` exists for scripts that must block:

```sh
bridge --wait page.html --timeout 900
```

Do not use it from a session; ending the turn is the way to wait, and it costs
nothing.

Full command list in `cli.md`.

## Notes and pins

The user's main way of answering is pointing. They press Point, click a spot,
type a note. Read them, answer them, close them:

```sh
bridge --pins page.html                      # open notes with their threads
bridge --working page.html <id>              # tell them you are on it
bridge --reply page.html <id> "done, and…"   # answer on the thread
bridge --done page.html <id>                 # close it (they can reopen)
```

A pin is anchored to the element by its tag, classes, position and text. **Keep
the classes on anything they might have pinned.** Rename or drop an element and
their pin goes grey and says it points at nothing. Rewording text under a pin is
fine; the pin follows.

A note with `"lost": true` in `--pins` is pointing at nothing: the element they
pointed at is gone from the page. Do not reply "fixed" or mark it done. Either
bring the element back (same tag and classes; the pin re-attaches on its own)
or reply asking what they meant, quoting `target`, which is what they pointed at.

## Revising a page

**Rewrite the same file.** Never `v2.html`. The window patches itself in place;
the user's scroll position, focus, half-written note and pins all survive.

What the rewrite changes decides what it costs:

- **Prose, wording, evidence, layout, images: free.** The user's answers
  stand, their Send stands, nothing is announced. Fix a typo without a second thought.
  One exception: a page that builds its content with a script (renders a
  list from data, say) cannot be patched, because the file does not hold
  what the script drew; it is reloaded instead, honestly, with a banner, and
  they lose their scroll position and any unsent note. So put the content in
  the markup and let a script only enhance it; a page written that way
  patches like any other.
- **The questions: a new version.** Adding, removing or renaming a
  `data-record` key, changing the offered `data-value`s, or changing what a
  control accepts (an input's type, a range's `min` or `max`, a select's
  options) moves their answers into history, takes their Send back, and shows
  them "changed since you answered" with what they said last time. They are told.
  `--read` shows `version: 2` and `history`. Do this when you mean it, not
  casually: tuning a range's bounds back and forth costs them a version each
  time. A range's `value` and `step` are free. A Write or Edit that makes a
  new version says so in its tool result, with what changed; read it.
- **Starting over:** `bridge --reset page.html`, then present it again. It
  forgets their answers, history and notes; the page is version 1. Never rename
  the file to escape its history.
- **Scripts:** changing a `<script>` in a plain page, or the code of a `.jsx`,
  reloads the page (honestly, with a banner). Data in `page.data.json` is
  pushed live without a reload, so put everything that changes there.

## When the window looks wrong

Look before you ask the user: `bridge --shot /tmp/…/window.png` writes a
picture of the app's window; then read the image. If the kit draws something wrong (a
readout covered, a control with no label), say so in your reply as a Bridge
bug with the markup that caused it, and suggest filing it at
https://github.com/medienbaecker/bridge/issues. Do not work around it by renaming the
file or rebuilding the page in another shape; the next agent hits it again.

## Ending a bridge

Taking the answer does not end it. When you have **acted** on the user's
answer, cross it on your way out so their list does not fill with finished work:

```sh
bridge --cross page.html
```

Presenting the file again brings it back to the top of their list and marks it
unread: that is how you say "I need you on this again".

## Rules

- Never `pbcopy`. A draft goes in a page with a Copy button.
- Never paste the page content into the chat as well. Say "in Bridge" and stop.
- Never three bare labels. Options carry evidence.
- Embed the real thing wherever it exists: the live site, the actual
  screenshot, the real diff numbers.
- Absolute paths for local images (`/Users/…/shot.png`), never relative.
- Any other file (`.log`, `.json`, `.diff`, `.php`) presents as text with a
  Copy button.
- Keep classes and structure on anything the user might have pinned.
- Rewrite the same file; never a new filename for a revision.
- Cross it when you are done with it.
- When the user reports a display bug, inspect their actual window with
  `bridge --state` rather than a fresh one.
- Code, diffs and compared numbers have components (pages.md "Evidence");
  do not hand-roll them.
