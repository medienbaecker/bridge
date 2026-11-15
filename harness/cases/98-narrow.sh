#!/bin/bash
source "$(dirname "$0")/../lib.sh"
export BRIDGE_TOOLKIT="$ROOT/toolkit"
page="$CASE_DIR/pages/narrow.html"
wide='<tr><td>Lorem&nbsp;ipsum&nbsp;dolor&nbsp;sit&nbsp;amet</td><td>consectetur&nbsp;adipiscing&nbsp;elit</td><td>sed&nbsp;do&nbsp;eiusmod&nbsp;tempor</td><td>incididunt&nbsp;ut&nbsp;labore&nbsp;et&nbsp;dolore</td></tr>'
cat > "$page" <<HTML
<!doctype html><html lang="de"><head><meta charset="utf-8"><title>Narrow</title></head><body>
<main id="main" style="max-width: 440px">
<h1 id="h1">Donaudampfschifffahrtsgesellschaftskapitänsmützenabzeichenherstellerverband</h1>
<p><a href="#" id="link">Lorem ipsum</a></p>
<div class="options">
  <div data-record="layout" data-value="a" id="card"><strong>Grundstücksverkehrsgenehmigungszuständigkeitsübertragungsverordnung</strong>Lorem ipsum</div>
  <div data-record="layout" data-value="b"><strong>Lorem</strong>Ipsum</div>
</div>
<fieldset class="options">
  <legend>Lorem ipsum?</legend>
  <div id="radio-card"><input type="radio" name="c" id="c-a" value="a" data-record="choice"><label for="c-a">Vermögenszuordnungszuständigkeitsübertragungsverordnungsänderungsgesetz</label><span>Lorem ipsum dolor sit amet.</span></div>
  <div><input type="radio" name="c" id="c-b" value="b" data-record="choice"><label for="c-b">Lorem</label><span>Ipsum</span></div>
</fieldset>
<fieldset id="fieldset" data-record="days"><legend>Lorem</legend><label><input type="checkbox" value="a"> Ipsum</label><label><input type="checkbox" value="b"> Dolor</label></fieldset>
<div class="bars"><div class="bar" style="--v: 100" id="bar"><span id="bar-label">Straßenverkehrszulassungsordnung</span><b>1.9 s</b></div></div>
<table id="plain"><thead><tr><th>Lorem</th><th>Ipsum</th><th>Dolor</th><th>Sit</th></tr></thead><tbody>$wide</tbody></table>
<table id="small"><tbody><tr><td>Lorem</td><td>12</td></tr></tbody></table>
<table class="data" id="data"><tbody>$wide</tbody></table>
<div class="compare" id="compare">
  <div><pre><code>const somethingVeryLong = aFunctionWithALongName(argumentNumberOne, argumentNumberTwo);</code></pre></div>
  <div><table><tbody>$wide</tbody></table></div>
</div>
<div class="dials"><label class="dial" id="preview-dial"><span>Lorem</span><input type="range" min="0" max="24" value="12"><output></output></label></div>
<div class="color" data-record="accent" value="oklch(0.62 0.19 250)"></div>
<label>Lorem <input type="text" value="Ipsum" disabled id="disabled-input"></label>
<div class="actions" id="actions">
  <button class="primary" id="on-yellow" style="--bridge-accent: #ffcc00">Lorem</button>
  <button class="primary" id="on-blue" style="--bridge-accent: #007aff">Ipsum</button>
  <button data-record="verdict" data-value="send" id="verdict">Lorem ipsum</button>
  <button data-record="verdict" data-value="rework">Dolor sit amet</button>
  <button disabled id="disabled-button">Consectetur</button>
  <button id="last">Grundstücksverkehrsgenehmigung beantragen</button>
</div>
</main>
</body></html>
HTML
printf '# Wide\n\n| Lorem | Ipsum | Dolor | Sit |\n| --- | --- | --- | --- |\n| %s | %s | %s | %s |\n' 'Lorem&nbsp;ipsum&nbsp;dolor&nbsp;sit&nbsp;amet&nbsp;consectetur&nbsp;adipiscing' 'sed&nbsp;do&nbsp;eiusmod&nbsp;tempor&nbsp;incididunt&nbsp;ut&nbsp;labore' 'et&nbsp;dolore&nbsp;magna&nbsp;aliqua&nbsp;ut&nbsp;enim&nbsp;ad&nbsp;minim' 'veniam&nbsp;quis&nbsp;nostrud&nbsp;exercitation&nbsp;ullamco' > "$CASE_DIR/pages/wide.md"
cat > "$CASE_DIR/pages/wide.jsx" <<'JSX'
import { Table, Card } from '@mantine/core';

export default function Page() {
  const cell = 'Lorem ipsum dolor sit amet consectetur adipiscing elit';
  return (
    <>
      <Table><Table.Tbody><Table.Tr><Table.Td>{cell}</Table.Td><Table.Td>{cell}</Table.Td><Table.Td>{cell}</Table.Td><Table.Td>{cell}</Table.Td></Table.Tr></Table.Tbody></Table>
      <Card withBorder data-record="layout" data-value="grid" id="card">Lorem</Card>
    </>
  );
}
JSX
repo
(cd "$CASE_DIR/pages" && bridge narrow.html 2>/dev/null); wait_ready; settle 0.6
js() { bridge --js "${at:-$page}" "$1" | jq -r .; }
fits="const fits = (id) => { const el = document.getElementById(id); return el.scrollWidth <= el.clientWidth && el.getBoundingClientRect().right <= document.getElementById('main').getBoundingClientRect().right + 0.5; };"
scrolls="const scrolls = (el) => el.hasAttribute('data-bridge-wide') && el.scrollWidth > el.clientWidth;"
sideways="document.documentElement.scrollWidth - document.documentElement.clientWidth"

check "the page does not scroll sideways, and it is as narrow as the case means it to be" "$(js "return ($sideways) + ' ' + document.getElementById('main').clientWidth")" "0 440"
check "a long word wraps inside the heading, the option card, the radio card and the bar's label" "$(js "$fits return ['h1', 'card', 'radio-card', 'bar-label'].map(fits).join(' ')")" "true true true true"
check "a wide table scrolls in its own box, plain and .data and inside .compare; one that fits is left a table" "$(js "$scrolls return [...document.querySelectorAll('table')].map((t) => (scrolls(t) ? 'scrolls' : getComputedStyle(t).display)).join(' ')")" "scrolls table scrolls scrolls"
check "the .compare columns share the width whatever is in them" "$(js "const [a, b] = [...document.getElementById('compare').children].map((c) => Math.round(c.getBoundingClientRect().width)); return a === b && a === (440 - 12) / 2")" "true"
check "the buttons wrap onto more rows and stay inside" "$(js "$fits const top = (id) => document.getElementById(id).getBoundingClientRect().top; return (top('last') > top('on-yellow')) + ' ' + fits('actions') + ' ' + fits('last')")" "true true true"
check "a plain fieldset has no border and no padding" "$(js "const s = getComputedStyle(document.getElementById('fieldset')); return s.borderTopWidth + ' ' + s.paddingLeft")" "0px 0px"
check "disabled controls are dimmed, enabled ones are not" "$(js "const o = (id) => getComputedStyle(document.getElementById(id)).opacity; return [o('disabled-button'), o('disabled-input'), o('last')].join(' ')")" "0.45 0.45 1"
check "a button that records is drawn as a button, not as a card" "$(js "const s = getComputedStyle(document.getElementById('verdict')); return s.paddingTop + ' ' + s.borderTopLeftRadius + ' ' + s.boxShadow")" "4px 6px none"
js "document.getElementById('verdict').click(); return 1" >/dev/null; settle 0.3
check "and shows that it is chosen" "$(js "const el = document.getElementById('verdict'); const s = getComputedStyle(el); return el.getAttribute('aria-pressed') + ' ' + (s.boxShadow !== 'none') + ' ' + (s.borderTopColor === getComputedStyle(document.getElementById('card')).borderTopColor)")" "true true false"
check "an accent button's text is dark on a light accent and white on a dark one" "$(js "const c = (id) => getComputedStyle(document.getElementById(id)).color; return c('on-yellow') + ' ' + c('on-blue')")" "oklch(0 0 0) oklch(1 0 0)"
check "a link is not the bare accent" "$(js "const probe = document.createElement('i'); probe.style.color = 'var(--bridge-accent)'; document.body.append(probe); const accent = getComputedStyle(probe).color; probe.remove(); return accent.startsWith('rgb') && getComputedStyle(document.getElementById('link')).color !== accent")" "true"
check "an option card can be reached by keyboard; a button that records needs no help" "$(js "const card = document.getElementById('card'), button = document.getElementById('verdict'); return [card.tabIndex, card.getAttribute('role'), button.hasAttribute('tabindex'), button.hasAttribute('role')].join(' ')")" "0 button false false"
js "document.getElementById('card').focus(); document.getElementById('card').dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', bubbles: true})); return 1" >/dev/null; settle 0.3
check_json "and Enter on it records" "$(bridge --read "$page")" '.answers.layout' "a"
check "a colour dial shows its gradient with nothing over it; a dial that only previews is grey" "$(js "const veil = (el) => getComputedStyle(el, '::before').backgroundColor; const l = document.querySelector('.bridge-color-dial'); return [veil(l) === 'rgba(0, 0, 0, 0)', veil(document.getElementById('preview-dial')) !== 'rgba(0, 0, 0, 0)', getComputedStyle(l).backgroundImage.startsWith('linear-gradient'), getComputedStyle(l.querySelector('span')).color].join(' ')")" "true true true rgb(255, 255, 255)"
shot narrow >/dev/null

at="$CASE_DIR/pages/wide.md"
(cd "$CASE_DIR/pages" && bridge wide.md 2>/dev/null); bridge --do select "$at" >/dev/null; wait_ready; settle 0.6
check "a wide Markdown table scrolls in its own box too" "$(js "$scrolls return ($sideways) + ' ' + (innerWidth > 300) + ' ' + scrolls(document.querySelector('table'))")" "0 true true"

at="$CASE_DIR/pages/wide.jsx"
(cd "$CASE_DIR/pages" && bridge wide.jsx 2>/dev/null); bridge --do select "$at" >/dev/null; wait_ready; settle 0.6
check "and so does a Mantine Table" "$(js "$scrolls return ($sideways) + ' ' + (innerWidth > 300) + ' ' + scrolls(document.querySelector('table'))")" "0 true true"
shot mantine >/dev/null
check "a Mantine Card that records can be reached by keyboard" "$(js "const card = document.getElementById('card'); return card.tabIndex + ' ' + card.getAttribute('role')")" "0 button"
finish
