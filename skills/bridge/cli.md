# The CLI

```sh
bridge <file|url> [more files]         present; html, jsx, md, txt, images, svg, pdf, or a URL; the first is selected
bridge --links <mode> <file|url>       where its links open: window (in Bridge), browser, or external (other hosts in the browser)
bridge --read   <file>                 what they have answered so far, JSON, no blocking
bridge --wait   <file> --timeout 900   block until they click Send (or close), then print
bridge --cross  <file>                 done with it: it folds away under "Crossed"
bridge --uncross <file>                bring it back
bridge --remove <file>                 take it off their list entirely (rare)
bridge --reset <file>                  remove it and forget their answers, history and notes: the next present is version 1
bridge --state                         what the app is showing right now, JSON
bridge --shot <out.png>                a picture of the app's window, to check what they see
bridge --waiters                       agent processes waiting for an answer, with age and memory, JSON
bridge --pins   <file>                 open notes with their threads
bridge --reply  <file> <id> <text>
bridge --done / --reopen / --working <file> <id>
bridge --hook stop [--timeout N]        the Claude Code Stop hook (installed once, not for agents)
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
yours, the message suggests a prefix from the title). Warnings (exit 0): a
colour or a border radius written out where `var(--bridge-*)` exists; a `pre`
whose lines are columns spaced by hand, or `language-*` on text that is not
that language. A page that loads a stylesheet from elsewhere is not checked
for unknown classes, since that sheet may define anything. The same checks
run once more when the page is presented, on the live DOM, and print to the
presenting command's stderr; lint is the one that arrives in time.

What the page's scripts throw while it loads (an uncaught error, an unhandled
rejection, a throw inside `bridge.ready`) prints there too, as
`bridge: page.html threw: <message> (page.html:12)`. A page that threw is
broken in the user's window; fix it before they look. WebKit hides the message
of an uncaught error in a top-level script on a `file://` page; that one
arrives as "a script threw", and moving the code into `bridge.ready(() => { … })`
gets the message and line on the next present.

## `--read`

```json
{
  "status": "open | sent | closed",
  "version": 2,
  "answers": { "layout": "grid", "radius": 12 },
  "defaults": [ "radius" ],                                           // in answers, but the page's proposal, not the user's
  "sent": "2026-09-20T13:31:32Z",
  "comments": [
    { "id": "3f9a1c2b", "text": "too heavy at phone width", "target": "strong \"List\"",
      "state": "open | working | done", "version": 2, "lost": false,
      "said": [ { "by": "agent", "at": "…", "text": "working on it", "kind": "status" },
                { "by": "agent", "at": "…", "text": "Dropped the padding", "kind": "reply" } ] }
  ],
  "history": [ { "version": 1, "answers": { "layout": "list" } } ],   // earlier versions' answers; never current
  "ground": { "repo": "/Users/…/site", "branch": "main", "commit": "cfa73c0", "headMoved": 3 }
}
```

A key under `defaults` is in `answers` because the page showed that value, not
because the user chose it: the control was pre-checked or pre-filled and they
never touched it. "They picked one number" and "the page defaulted to one
number and they never looked" are different facts; act on the second as a
proposal, not a decision.

If another session presented the bridge you get `{ "status", "heldBy", "note" }`
and no answers, until the answer is two hours old. Presenting the file yourself
takes it over.

## `--state`

Selection, title, status, version, answer and note counts, every toolbar item
with its label and whether it is enabled, and the sidebar as the user sees it
(one row per bridge: title, age, waiting, unread, crossed). `{"running": false}`
when the app is not up. Use it to check a report against their actual window.

## The Stop hook

`bridge --hook stop` is registered as a Claude Code Stop hook with
`asyncRewake` (see `install/stop-hook.json`), so it is detached once the turn
has ended and the session goes idle as usual. It looks for an uncollected
answer to a bridge this session presented (or an answer nobody collected for
two hours) and, if the session still has bridges open, keeps watching for
one. When it has an answer it writes the hand-over to stderr and exits 2,
which wakes the session with that text. It exits 0 at once when nothing is
open and on any error.

## The write hook

`bridge --hook post-write` is registered as a PostToolUse hook on Write and
Edit. When the file written is a bridge and the write made a new version, the
agent's tool result carries the new version number and what changed. When the
page threw after the write, the tool result says what. Any other write is
silent.

`bridge --hook session`, on SessionStart, UserPromptSubmit and SessionEnd,
records whether a session is alive and in a turn, so a row nobody waits on
says "agent working" or "session ended" instead of "no agent waiting".

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
