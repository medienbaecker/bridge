# The CLI

```sh
bridge <file|url> [more files]         present; html, jsx, md, txt, images, svg, pdf, or a URL; the first is selected
bridge --links <mode> <file|url>       where its links open: window (in Bridge), browser, or external (other hosts in the browser)
bridge --site <url> <file.html>        run the page as part of a local site: it imports the site's modules and reaches into its frames
bridge --read   <file>                 what they have answered so far, JSON, no blocking
bridge --wait   <file> --timeout 900   block until they click Send (or close), then print
bridge --cross  <file>                 done with it: it folds away under "Crossed"
bridge --uncross <file>                bring it back
bridge --remove <file>                 take it off their list entirely (rare)
bridge --reset <file>                  remove it and forget their answers, history and notes: the next present is version 1
bridge --state                         what the app is showing right now, JSON
bridge --shot <out.png>                a picture of the app's window, to check what they see
bridge --shot <file> <out.png> [--width N] [--site <url>]   the page rendered off-screen, as the window would show it, without presenting it; waits for its frames
         [--crop x,y,w,h]               only that area, in CSS pixels from the page's top left
         [--zoom N]                     the window's own pixels enlarged N times (1 to 8), unsmoothed: shows half-pixel blur
         [--scale N]                    painted again at N pixels per CSS pixel (1 to 8, default 2): sharp detail
bridge --reload <file>                 reload the page and its frames from scratch, e.g. after the site's CSS changed
bridge --waiters                       agent processes waiting for an answer, with age and memory, JSON
bridge --pins   <file>                 open notes with their threads
bridge --reply  <file> <id> <text>
bridge --done / --reopen / --working <file> <id>
bridge --share <file>                  send a page and the files it shows to the other connected Macs
bridge --peers                         the other Macs with Bridge this one knows, and which are connected, JSON
bridge --name [name]                   this Mac's person on shared pages; with a name, set it
bridge --colour [#hex|none]            this person's cursor colour on shared pages
```

Files are resolved against the current directory. Present from inside the
project's repo: the page is grouped under that project in the user's list, and
the answer records repo, branch and commit.

A URL defaults to `--links external`: the user can click around the site and a
link to another host opens in their browser. A file defaults to `browser`. The
mode holds until the next present, which sets it again. A `target="_blank"`
link always opens in the browser.

## `--lint`

`bridge --lint page.html [more]` checks a page against the kit before it is
presented, one finding per line as `file:line: level: what to do`. Errors
(exit 1): a class no stylesheet defines, with the nearest thing in the
vocabulary or the shape the word usually wants; a class the page's own
`<style>` and the kit both define, which lands both on the element (rename
yours, the message suggests a prefix from the title). Warnings (exit 0):
colours of the page's own with no dark variant, or a colour in a `style`
attribute, which no dark variant can reach; a `pre`
whose lines are columns spaced by hand, or `language-*` on text that is not
that language; two or more `h2`/`h3` sections where one sits in no element
with an `id` or `data-record`, so notes on it carry no name. A page that loads a stylesheet from elsewhere is not checked
for unknown classes, since that sheet may define anything. Presenting runs
the same lint first: a page with errors is not presented (exit 1) and the
window stays where it is; warnings do not stop it. The
checks run once more on the live DOM after it opens and print there too.

What the page's scripts throw while it loads (an uncaught error, an unhandled
rejection, a throw inside `bridge.ready`) prints there too, as
`bridge: page.html threw: <message> (page.html:12)`. A page that threw is
broken in the user's window; fix it before they look.

## `--read`

```json
{
  "status": "open | sent | closed",
  "version": 2,
  "answers": { "layout": "grid", "radius": 12 },
  "defaults": { "size": "m" },                                        // the page's values the user left untouched; never in answers
  "withdrawn": [ "tone" ],                                            // answered at the last Send, taken back since; only when there is one
  "sent": "2026-09-20T13:31:32Z",
  "comments": [
    { "id": "3f9a1c2b", "text": "too heavy at phone width", "target": "strong \"List\" in #layout › layout=list",
      "state": "open | working | done", "version": 2, "lost": false,
      "said": [ { "by": "agent", "at": "…", "text": "working on it", "kind": "status" },
                { "by": "agent", "at": "…", "text": "Dropped the padding", "kind": "reply" } ] }
  ],
  "history": [ { "version": 1, "answers": { "layout": "list" } } ],   // earlier versions' answers; never current
  "ground": { "repo": "/Users/…/site", "branch": "main", "commit": "cfa73c0", "headMoved": 3 }
}
```

`answers` holds only what the user chose. A key under `defaults` is there
because the page showed that value and they never changed it: the control was
pre-checked or pre-filled. "They picked one number" and "the page defaulted to
one number and they never looked" are different facts; act on the second as a
proposal, not a decision. Setting a control back to the page's value, a second
click on the chosen card or radio, or emptying a field takes the answer back,
so a key can leave `answers` again.

If another session presented the bridge you get `{ "status", "heldBy", "note" }`
and no answers, until the answer is two hours old. Presenting the file yourself
takes it over.

## `--state`

Selection, title, status, version, answer and note counts, every toolbar item
with its label and whether it is enabled, and the sidebar as the user sees it
(one row per bridge: title, age, waiting, unread, crossed). `{"running": false}`
when the app is not up. Use it to check a report against their actual window.

## Shared pages

Two people can share a page across their Macs. Bridges on the same network
find and trust each other on their own; a page is shared with the toolbar's
"Share with …" button, by dropping it on the person in the sidebar, or with
`bridge --share <file>`. The page
and the local files it shows are copied to the other Mac, and from then on
both people see each other's cursors, picks, typing and notes.

- `--read` on a shared page keeps `answers` as this Mac's person's picks and
  adds `people`: every person's picks by name. Notes and replies carry
  `person`.
- A page that arrived from the other Mac lives in Bridge's state dir under
  `shared/`. Reading it (`--read` or `--pins`) makes your session its holder,
  so this Mac's Send wakes you. The person can also hand it to another
  session with the agent menu in the toolbar.
- Rewrite a shared page as you would any page. The rewrite reaches the other
  Mac and its window patches in place. Image paths are mapped for you.
  If the other agent rewrote it since you read it, Claude Code asks you to
  read it again; do, and keep their change.
- Each person's Send wakes only their own agent.

## How an answer reaches you

Claude Code keeps a record of every live session and gives each one an inbox
socket. When the user sends or closes a page, the Bridge app posts the
hand-over to the inbox of the session holding it, which wakes that session if
it is idle. A session that has ended gets it when it is resumed. Reading the
answer yourself first (`--read`) means nothing is posted.

## The write hook

`bridge --hook post-write` is registered as a PostToolUse hook on Write and
Edit. When the file written is a bridge and the write made a new version, the
agent's tool result carries the new version number and what changed. When the
page threw after the write, the tool result says what. Any other write is
silent.

## Files on disk

The answer sidecar lives in the app's store, not beside the page
(`bridge --sidecar page.html` prints the path, under
`~/.local/state/<flavour>/answers/`). It is plain JSON and survives the app
not running; `--read` reads it directly. Do not edit it by hand.

A `page.html.bridge.json` beside a page comes from an older version and is
renamed `.bridge.json.migrated` on first touch; never read either as the
record.

## Environment

- `BRIDGE_SESSION` names your session for the "only the presenting session
  hears the answer" rule; the terminal's tty is used when it is unset.
- `XDG_STATE_HOME` moves the app's state (list, versions, builds). The
  socket is under `$TMPDIR`, named after the state dir.
