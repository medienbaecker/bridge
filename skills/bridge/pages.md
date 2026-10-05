# Plain pages

A plain page is one `.html` file. Bridge injects a stylesheet that makes
semantic HTML look like a macOS panel in light and dark, following the system
accent. Write the content; do not write CSS unless you need something the base
does not give you. No `<style>` for fonts, colours or backgrounds.

## How recording works

- `data-record="key"` on an element makes it a question.
- Clickable options: elements with `data-record` **and** `data-value`. Clicking
  records the value and marks the chosen one (`data-selected`). Siblings with
  the same key are one question.
- Form controls: `<input>`, `<select>`, `<textarea>` with `data-record` record
  their value (`type=range`/`number` as numbers, checkbox as boolean,
  `select multiple` as an array). Radio and checkbox groups: put `data-record`
  on the wrapper; radios record the chosen value, checkboxes an array.
- `contenteditable` inside a `data-record` element records its text.
- `data-send` on a button: pressing it is Send (the toolbar has one too).
  On an option (`data-record` + `data-value`) it records the value and sends.
- `data-copy="#selector"` on a button copies that element's text (or a
  textarea's value) and shows "Copied".
- Two rewrites with the same keys and offered values are the same version.

### Recording from a script: an editor

A page where the user works on content rather than picks an option (a script
they write, a list they reorder) has state that no control owns. The page's
scripts get `window.bridge`:

```html
<textarea id="script"></textarea>
<script>
  const box = document.getElementById("script");
  bridge.ready(() => { box.value = bridge.get("script", { own: true }) || ""; });
  box.addEventListener("input", () => bridge.set("script", box.value));
</script>
```

- `bridge.set(key, value)` records like a `data-record` control (debounced;
  `--read` shows it under `answers`). A third argument is accepted and
  ignored.
- `bridge.get(key)` returns what the record holds; call it inside `bridge.ready`.
  A page that restores its state must ask for the user's values only:
  `bridge.get(key, { own: true })` is `undefined` for a value the page itself
  proposed (a checked radio, a range's value) and they never touched, and
  `bridge.isDefault(key)` says which it is. Restoring a default as if they had
  chosen it puts back a proposal the page may have stopped making.
- `bridge.ready(fn)` runs `fn` once the user's answers are available, before
  the page is hashed, so keys read there are its questions from the start.

A key the page touches this way is one of its questions from then on, on
every later open too. A page declaring a key by its own action is not a new
version; a rewrite that adds or drops a
`data-record` question still is. A rewrite that simply stops calling `get`
for a key is not detected: the key stays a question until the sidecar is
removed.

## Shapes

### Decision

```html
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Card layout for the archive</title></head>
<body>
<h1>Card layout for the archive</h1>
<p class="muted">The archive has 140 entries. Two layouts survive the content; pick one.</p>

<h2>Layout</h2>
<div class="options">
  <div data-record="layout" data-value="grid" tabindex="0">
    <img src="/Users/you/Projects/site/shots/grid.png" alt="">
    <strong>Grid</strong>
    Three columns at desktop. Titles wrap to two lines on 12 of 140 entries.
  </div>
  <div data-record="layout" data-value="list" tabindex="0">
    <img src="/Users/you/Projects/site/shots/list.png" alt="">
    <strong>List</strong>
    One entry per row. Nothing wraps; the page is 4.5 screens tall.
  </div>
</div>

<h2>Corner radius</h2>
<label>Radius <input type="range" data-record="radius" min="0" max="24" value="8"></label>

<h2>Anything else</h2>
<textarea data-record="note" placeholder="Optional"></textarea>

<div class="actions"><button data-send>Send</button></div>
</body>
</html>
```

`.options.stack` stacks options in one column. Put `<strong>` first in an
option: it becomes the option's name in "last time" hints.

Options can also be radios, which is the right shape when the page is a
`<fieldset>` with a `<legend>` question, or when the options need a real
form control for assistive tech. Each card is a block with the radio first,
a `<label for>` as its title, and a `<span>` as its description; the chosen
card is marked by the browser:

```html
<fieldset class="options">
  <legend>Question 1?</legend>
  <div>
    <input type="radio" name="choice" id="c-a" value="a" data-record="choice">
    <label for="c-a">Option A</label>
    <span>Lorem ipsum dolor sit amet.</span>
  </div>
</fieldset>
```

Both shapes record the `value`; do not switch a page from one to the other
after the user has answered it (that changes what the page asks).

A `checked` radio or checkbox, a range or select with a value, is a
proposal: the record carries it from the moment the user sees the page, and
names the key under `defaults` until they touch the control. If your page's
outcome depends on them actually deciding, do not pre-check it.

### Key and value

Numbers with names, as a list rather than prose. Use `.bars` when the numbers
compare; use `.metrics` when they are just facts:

```html
<dl class="metrics">
  <div><dt>bridges in your list</dt><dd>14</dd></div>
  <div><dt>waiting on you</dt><dd>3</dd></div>
</dl>
```

A bar can carry a tone: `data-tone="warn"` or `data-tone="bad"` on `.bar`.

A label with a value at the right, one per row, is `.row.between`: the label
takes the width, the value is a `.num` on the label's first baseline, so a
column of them lines up whatever the labels' lengths. A bordered `.card`
groups such rows:

```html
<div class="card">
  <div class="row between"><span><strong>Item 1</strong> · detail<br><span class="muted">Lorem ipsum</span></span><span class="num">2 h</span></div>
  <hr>
  <div class="row between"><span><strong>Item 2</strong></span><span class="num">1 h</span></div>
</div>
```

### Swatches

A handful of colours to pick from, with a hex field for one that is not
offered. Buttons carry `data-color`; the group records the hex and can drive
a property. For tuning a colour by feel use `.color` instead.

```html
<div class="swatches" data-record="tint" data-drive="--tint" data-target="#preview">
  <button type="button" data-color="#2f6feb"></button>
  <button type="button" data-color="#1a7f4b"></button>
  <input type="text" value="#2f6feb" spellcheck="false" aria-label="Hex">
</div>
```

### Draft with a Copy button

```html
<h1>Reply to Alex</h1>
<p class="muted">Short reply, informal.</p>
<pre class="draft" id="draft">Hi Alex,

lorem ipsum dolor sit amet …</pre>
<div class="actions">
  <button data-copy="#draft" class="primary">Copy</button>
  <button data-record="verdict" data-value="send">Send as is</button>
  <button data-record="verdict" data-value="rework">Rework</button>
</div>
<textarea data-record="changes" placeholder="What to change"></textarea>
```

Never also print the draft in the chat.

### Screenshots: grid and before/after

```html
<h2>All four breakpoints</h2>
<div class="shots">
  <figure><img src="/abs/path/320.png" alt=""><figcaption>320</figcaption></figure>
  <figure><img src="/abs/path/768.png" alt=""><figcaption>768</figcaption></figure>
</div>

<h2>Before / after</h2>
<div class="wipe">
  <img src="/abs/path/before.png" alt="">
  <img src="/abs/path/after.png" alt="">
  <input type="range" min="0" max="100" value="50" aria-label="Wipe">
</div>
```

The user drags across the wipe. They can point at any pixel of either.

### Evidence: code, diffs, bars

`pre` and `language-*` are for source code and command output, nothing
else: a `pre` says "this is code" to the user, and columns spaced with
literal spaces break the first time a value gets longer. Aligned data is a table
(next section). Code blocks with a `language-` class are highlighted (html,
css, js, php, bash, json, yaml). A unified diff in `language-diff` gets its
added and removed lines coloured; paste `git diff` output as it is.

```html
<pre><code class="language-php">&lt;?php return $page->children()->listed();</code></pre>
<pre><code class="language-diff">- $items = $page->children();
+ $items = $page->children()->listed();</code></pre>
```

Numbers the user should compare get bars, no library: `--v` is the length in
percent of the widest.

```html
<div class="bars">
  <div class="bar" style="--v: 100"><span>Grid</span><b>1.9 s</b></div>
  <div class="bar" style="--v: 63"><span>List</span><b>1.2 s</b></div>
  <div class="bar" style="--v: 41" data-muted><span>Today</span><b>0.8 s</b></div>
</div>
```

### Aligned data: the annotated table

Rows of things with a few facts each (an id, its current value, where it
came from) are a `table.data`: the cells align, an optional `.remark` cell
trails quietly, and a `tbody` per group breaks the rows apart. This is the
shape for what would otherwise be a hand-spaced `pre`.

```html
<table class="data">
  <tbody>
    <tr><td><code>#item-1</code></td><td>"Lorem ipsum dolor"</td><td class="remark">fallback</td></tr>
    <tr><td><code>#item-2</code></td><td>…</td><td class="remark">fallback</td></tr>
  </tbody>
  <tbody>
    <tr><td><code>#item-1</code></td><td>"Sit amet consectetur"</td><td class="remark">the original</td></tr>
    <tr><td><code>#item-3</code></td><td>"Adipiscing elit"</td><td></td></tr>
  </tbody>
</table>
```

### Tuning by feel: dials and colour

Numbers the user tunes by feel are dials, not sliders: one filled row per
value, draggable anywhere across the row, label left, readout right. Six of them
read as a property list to play with, not a form to fill in. Underneath is a
real range input, so keyboard and screen readers work.

```html
<div class="dials">
  <label class="dial"><span>Radius</span><input type="range" data-record="radius" data-drive="--radius" data-unit="px" data-target=".preview" min="0" max="24" step="0.5" value="8"><output></output></label>
  <label class="dial"><span>Ease</span><input type="range" data-record="ease" data-drive="--ease" min="0" max="1" step="0.001" value="0.35"><output></output></label>
</div>
```

A dial with `data-record` is a question and wears the accent; one with only
`data-drive` moves the preview, answers nothing and is grey. The user sees
which is which before they touch either, and a control holding their answer is marked at
the control. So a key means "this is a question": a dial that only drives a
preview must not carry one "to be safe".

**Set `step` an order of magnitude finer than seems necessary.** A step the
user can feel but not land on is worse than no control: 0.05 over 0 to 1 gives them
twenty positions and they wanted the one between two of them. The readout
carries the precision; `data-unit` is appended to it.

A colour is a `.color` element, never `<input type="color">` (WebKit opens
the system picker at the bottom of the window, detached from the thing being
recoloured). It is three OKLCH dials with a swatch, a hex field and a gamut
readout (sRGB, P3, out of gamut); it records the colour as an `oklch()`
string and drives a custom property with it, so a colour can be tuned against
a live site like any number:

```html
<div class="color" data-record="accent" data-drive="--accent" value="oklch(0.62 0.19 250)"></div>
```

### Controls that drive the preview

A control that only records is decoration. Give it `data-drive` and it sets a
CSS custom property as it moves, on the elements it names in this page and,
if the page embeds a live site, on that site's root as well:

```html
<style>.preview { border-radius: var(--radius, 4px); padding: var(--pad, 8px) }</style>
<label>Radius <input type="range" data-record="radius" data-drive="--radius" data-unit="px" data-target=".preview" min="0" max="24" value="4"></label>
<label>Padding <input type="range" data-record="pad" data-drive="--pad" data-unit="px" min="0" max="48" value="10"></label>
<div class="preview">The thing being decided</div>
<iframe src="https://site.test/archive" style="width:100%;height:520px"></iframe>
```

- `data-drive="--prop"` names the property; `data-unit` is appended
  (`px`, `rem`, `ms`, `%`, or nothing for colours and keywords).
- `data-target` is a selector in this page (default `:root`).
  `data-frame-target` is a selector inside the embedded site (default its
  `:root`, so `var(--pad)` anywhere in the site follows the slider).
- The user's recorded values are applied again when the page is reopened, so
  what they see matches what `--read` returns.
- The site must use the property: `padding: var(--pad, 10px)` in its CSS. For
  a site you are editing that is the point: wire the property into the real
  stylesheet, present the page, and let the user tune it in place.

In a `.jsx` page use an inline style for your own tree
(`style={{ '--radius': radius + 'px' }}`) and `drive('--pad', pad + 'px')`
from `@bridge` to reach an embedded site.

### Code as evidence

A `pre` is already a panel. Never wrap it in `.evidence`: the kit paints
nothing for a surface inside a surface, so the doubled box cannot appear,
but the padding you meant is lost too. `.evidence` is for a factual line or
two (a number, a measurement, a quote), not a container.

```html
<p>The template puts the language switch inside the nav:</p>
<pre><code class="language-html">&lt;nav&gt;…&lt;/nav&gt;</code></pre>
```

### A finding that needs explaining

The common hard case: a complicated finding that has to be understood before
it can be decided. Lead with the decision, put under it only the evidence
that decides it, and keep the page to about a screen and a half. Two long
code blocks, a table, an iframe and eleven paragraphs before the first
question make a page four windows tall, and a good analysis does not save it.
If the analysis genuinely needs more,
the rest goes in a `<details>` they can open, or in chat. One question per
page; two at most, and never three.

### Explorable

How a piece of code works, shown by running it and letting the user move it:

- Run the real code: import the project's module directly, by a path
  relative to the page or an absolute file path, as below. For a look, embed
  the real site in a frame instead.
- One step per heading: a heading that states the point, one line that
  starts with a verb, then a big visual.
- The page makes its point before anyone touches it; controls are for going
  deeper.
- Give each control a question: let them set where they think it lands
  ("Where is it at 0.5 s?"), then reveal what the real code does.
- Next to a slider, show key states at once: a row of small multiples, such
  as the trace at three stiffnesses.
- Slow down what is too fast to see: record one cycle, then a step button
  and a scrubber over it, not autoplay.
- Labels and readouts sit next to what they describe, axes are labelled.
- For tuning, one control drives everything on the page.
- Silent by default; any sound starts only after a click.

A module whose own imports are bare package names (`from 'three'`) needs
bundling first: `npx esbuild src/rope.js --bundle --format=esm --outfile=rope.js`.

```html
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>The spring</title>
<style>
  .steps { display: grid; grid-template-columns: 1fr 1fr; gap: 32px; }
  svg { display: block; width: 100%; height: auto; touch-action: none; }
  #cord { stroke: var(--bridge-muted); stroke-width: 2; fill: none; }
  svg line { stroke: var(--bridge-line); }
  svg text { fill: var(--bridge-muted); font-size: 14px; font-variant-numeric: tabular-nums; }
  #weight, #dot { fill: var(--bridge-accent); }
  #ghost { fill: var(--bridge-accent); fill-opacity: 0.3; cursor: grab; }
  #trace, #m1 { stroke: var(--bridge-accent); stroke-width: 2; fill: none; }
  #m0, #m2 { stroke: var(--bridge-muted); stroke-width: 1.5; fill: none; }
  #marker { stroke: var(--bridge-muted); }
  #t { flex: 1; max-width: 440px; }
</style></head>
<body>
<h1>The spring</h1>
<div class="dials">
  <label class="dial"><span>Stiffness</span><input id="k" type="range" min="1" max="200" step="0.1" value="60"><output></output></label>
  <label class="dial"><span>Damping</span><input id="damping" type="range" min="0" max="20" step="0.01" value="3"><output></output></label>
</div>

<div class="steps">
<section>
<h2>1. Where is it at 0.5 s?</h2>
<p class="muted">Drag the ghost to your guess, then reveal what step() does.</p>
<svg id="spring" viewBox="0 0 400 170">
  <line x1="40" y1="80" x2="400" y2="80"></line>
  <text x="0" y="84">x 0</text>
  <polyline id="cord"></polyline>
  <circle id="weight" cx="140" r="14"></circle>
  <text id="readout" x="164"></text>
  <circle id="ghost" cx="280" cy="80" r="14"></circle>
  <text id="guess" x="304"></text>
</svg>
<div class="row"><button id="reveal">Reveal</button><span id="gap" class="muted"></span></div>
</section>
<section>
<h2>2. One second, slowed down</h2>
<p class="muted">Step or scrub through one release from x = 60.</p>
<svg id="plot" viewBox="0 0 400 170">
  <line x1="30" y1="80" x2="400" y2="80"></line>
  <text x="0" y="84">x 0</text><text x="378" y="168">1 s</text>
  <path id="trace"></path>
  <line id="marker" x1="30" y1="0" x2="30" y2="160"></line>
  <circle id="dot" r="4"></circle>
  <text id="at" y="12"></text>
</svg>
<div class="row"><button id="next">Next step</button><input id="t" type="range" min="0" max="60" step="1" value="0" aria-label="Time"></div>
<svg id="multiples" viewBox="0 0 400 96">
  <line x1="0" y1="36" x2="120" y2="36"></line><line x1="140" y1="36" x2="260" y2="36"></line><line x1="280" y1="36" x2="400" y2="36"></line>
  <path id="m0"></path><path id="m1"></path><path id="m2"></path>
  <text id="l0" x="0" y="92"></text><text id="l1" x="140" y="92"></text><text id="l2" x="280" y="92"></text>
</svg>
</section>
</div>

<script type="module">
import { step } from './spring.js';
const $ = (id) => document.getElementById(id);
const params = () => [Number($('k').value), Number($('damping').value)];
const frames = 60, rest = 80, release = 60, px = (i) => 30 + i * 370 / frames, py = (x) => 80 + x * 0.9;
let guess = 0, held = false, trace = [];

function hang(x) {
  $('weight').setAttribute('cy', rest + x);
  $('cord').setAttribute('points', Array.from({ length: 14 }, (_, i) => `${i % 2 && i < 13 ? 140 + (i % 4 === 1 ? 10 : -10) : 140},${i * (rest + x - 14) / 13}`).join(' '));
  $('readout').setAttribute('y', rest + x + 4);
}
function reset() {
  hang(release);
  $('readout').textContent = `release x ${release}`;
  $('gap').textContent = '';
}
function place() {
  $('ghost').setAttribute('cy', rest + guess);
  $('guess').setAttribute('y', rest + guess + 4);
  $('guess').textContent = `guess x ${guess.toFixed(0)}`;
}
$('ghost').addEventListener('pointerdown', () => { held = true; });
addEventListener('pointermove', (e) => {
  if (!held) return;
  const p = new DOMPoint(e.clientX, e.clientY).matrixTransform($('spring').getScreenCTM().inverse());
  guess = Math.max(-70, Math.min(70, p.y - rest));
  place();
});
addEventListener('pointerup', () => { held = false; });
$('reveal').addEventListener('click', () => {
  let x = release, v = 0, i = 0;
  const tick = () => {
    [x, v] = step(x, v, ...params());
    hang(x);
    if (++i < frames / 2) return requestAnimationFrame(tick);
    $('readout').textContent = `0.5 s  x ${x.toFixed(0)}`;
    $('gap').textContent = `off by ${Math.abs(x - guess).toFixed(0)}`;
  };
  tick();
});

function run(k) {
  const out = [[release, 0]];
  for (let i = 1; i <= frames; i++) out.push(step(...out[i - 1], k, params()[1]));
  return out;
}
function record() {
  trace = run(params()[0]);
  $('trace').setAttribute('d', trace.map(([x], i) => `${i ? 'L' : 'M'}${px(i)} ${py(x)}`).join(' '));
  [0.5, 1, 2].forEach((f, n) => {
    const k = params()[0] * f;
    $(`m${n}`).setAttribute('d', run(k).map(([x], i) => `${i ? 'L' : 'M'}${n * 140 + i * 120 / frames} ${36 + x * 0.5}`).join(' '));
    $(`l${n}`).textContent = `stiffness ${k.toFixed(0)}`;
  });
  scrub();
  reset();
}
function scrub() {
  const i = Number($('t').value), [x, v] = trace[i];
  for (const a of ['x1', 'x2']) $('marker').setAttribute(a, px(i));
  $('dot').setAttribute('cx', px(i));
  $('dot').setAttribute('cy', py(x));
  $('at').setAttribute('x', Math.min(px(i) + 6, 250));
  $('at').textContent = `${(i / frames).toFixed(2)} s  x ${x.toFixed(1)}  v ${v.toFixed(1)}`;
}
$('t').addEventListener('input', scrub);
$('next').addEventListener('click', () => { $('t').value = (Number($('t').value) + 1) % (frames + 1); scrub(); });
for (const id of ['k', 'damping']) $(id).addEventListener('input', record);
place();
record();
</script>
</body>
</html>
```

Whenever the page re-implements something instead of importing it, show a
check that runs the real code on the same input and says whether the result
matches. A convincing wrong explanation is worse than none:

```js
const real = [[80, 0]];
for (let i = 1; i < trace.length; i++) real.push(step(...real[i - 1], ...params()));
const off = trace.findIndex(([x], i) => Math.abs(x - real[i][0]) > 1e-9);
$('check').textContent = off < 0 ? 'Matches spring.js' : `Differs from spring.js at frame ${off}`;
```

with `<p class="evidence" id="check"></p>` next to the picture it vouches for.

### Live site next to evidence

```html
<h2>The page as it is now</h2>
<iframe src="http://site.test/archive" style="width:100%;height:520px;border:1px solid var(--bridge-line);border-radius:8px"></iframe>
```

The frame earns its place by what is around it. For a site the user should
only look at, give them the URL in your reply; present it directly
(`bridge http://site.test/archive`) only when they should pin spots on it.

A link clicked in the frame stays in the frame when it goes to the same host
and opens in the user's browser when it goes elsewhere. Set
`data-links="window"` on the iframe to keep every link in the frame, or
`data-links="browser"` to send every link out. A `target="_blank"` link always
opens in the browser.

Any site loads in a frame unless it refuses to be framed with
`X-Frame-Options` or CSP `frame-ancestors`, which every browser obeys.
Presenting the page names a frame that refuses on stderr, and the page says
so above the blank frame. Then present the URL on its own (it loads as the
page, and the user can pin it), or put a local proxy in front of it that drops
those two headers. A proxy that passes them through is still refused.

### Plan

Write `plan.md`. Headings, lists, tables, task lists and code all render.
Nothing to answer: the user crosses it when they have read it, or leaves notes.

### Sound

A page is a `file://` document. Workers, `import()` and `fetch()` from blob
URLs work, but an AudioWorklet module from a blob URL is refused ("Cross-origin
script load denied"). Write the processor to a file beside the page and load
that; no local server needed:

```js
const ctx = new AudioContext();
await ctx.audioWorklet.addModule('synth-processor.js'); // a file next to the page
```

## Pages written for another kit

A page that styles itself with variables from elsewhere (`--ink`, `--paper`,
`--rule`, `--accent`, `--surface`) renders here with those rules silently
resolving to nothing. The kit defines only `--bridge-accent`,
`--bridge-muted`, `--bridge-line`, `--bridge-panel` and `--bridge-radius`;
use those, or `Canvas`/`CanvasText` for surface and text.

## What the base stylesheet gives you

`h1 h2 h3 p ul ol table pre code img figure figcaption hr small .muted`,
`.options` (grid of option cards), `.options.stack`, `.row` (flex row),
`.row.between` with `.num` (label and value on one line), `.card` (bordered
box), `.actions` (button row with top margin), `.compare` (two columns),
`.evidence` (quiet panel for a factual line or two), `.draft` (pre-wrapped
text panel), `.shots` (screenshot grid), `.wipe` (before/after), `.bars` and
`.bar` (compared numbers), `.metrics` (key and value), `.data` with `.remark`
(annotated table), `.swatches` (a few colours to pick from), `.dials` and `.dial` (tuning by feel), `.color` (OKLCH colour),
`.language-*` on `code` (highlighting; `.language-diff` for diffs),
`.primary` and `[data-send]` (accent button), `.button` (a link that looks
like one). Colours: `var(--bridge-accent)`, `var(--bridge-muted)`,
`var(--bridge-line)`, `var(--bridge-panel)`.

Nothing else exists. A class the kit does not define and the page does not
define in its own `<style>` styles nothing, and the CLI says so on stderr
when it presents the page (`bridge: unknown classes: …`); write the style or
use a shape from this list.
