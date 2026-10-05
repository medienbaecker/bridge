function __bridgeInit(options) {
  if (globalThis.__bridge) return;
  const handler = window.webkit.messageHandlers.bridge;
  const post = (type, data = {}) => handler.postMessage({ type, ...data });

  // Inside an embedded frame (a live site in an iframe) the runtime only
  // receives driven CSS properties; everything else belongs to the top page.
  if (window !== window.top) {
    globalThis.__bridge = {
      drive(prop, value, target) {
        for (const el of document.querySelectorAll(target || ':root')) el.style.setProperty(prop, value);
      },
    };
    const announce = () => post('frame-ready', { url: location.href });
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', announce); else announce();
    return;
  }
  const state = { answers: {}, status: 'open', readOnly: false, pointing: false, notes: [], previous: null, timers: {}, patches: 0, refused: {} };
  const root = document.documentElement;

  const style = document.createElement('style');
  style.className = 'bridge-style';
  style.textContent = (options.local ? __BRIDGE_CSS.page + '\n' : '') + __BRIDGE_CSS.ui;
  root.appendChild(style);

  const ours = (node) => node.nodeType === 1 && [...(node.classList || [])].some((c) => c.startsWith('bridge-'));

  // ---- answers

  function valueOf(el) {
    switch (el.type) {
      case 'checkbox': return el.checked;
      case 'number': case 'range': return el.value === '' ? null : Number(el.value);
      case 'select-multiple': return [...el.selectedOptions].map((o) => o.value);
      default: return el.value;
    }
  }

  // A dial that records looks like one that only previews, so a control holding
  // an answer is marked, or a value tried in passing gets sent by mistake.
  function markAnswered(key, on) {
    const k = CSS.escape(key);
    for (const el of document.querySelectorAll(`input[data-record="${k}"]:not([type=checkbox]):not([type=radio]), select[data-record="${k}"], textarea[data-record="${k}"], .color[data-record="${k}"]`)) {
      el.toggleAttribute('data-answered', on);
      (el.closest('.dial') || el).title = on ? 'Your answer' : '';
    }
  }

  function record(key, value, delay) {
    if (state.readOnly) return;
    state.answers[key] = value;
    markAnswered(key, true);
    if (state.status === 'sent') setStatus('open');
    clearTimeout(state.timers[key]);
    if (delay) state.timers[key] = setTimeout(() => post('record', { key, value }), 150);
    else post('record', { key, value });
  }

  function select(el) {
    const key = el.dataset.record;
    for (const sibling of document.querySelectorAll(`[data-record="${CSS.escape(key)}"][data-value]`)) {
      const on = sibling === el;
      sibling.toggleAttribute('data-selected', on);
      sibling.setAttribute('aria-pressed', on);
    }
  }

  function applyAnswers(answers) {
    for (const el of document.querySelectorAll('[data-record][data-value][data-selected]:not(.color)')) {
      if (!(el.dataset.record in answers)) { el.removeAttribute('data-selected'); el.setAttribute('aria-pressed', 'false'); }
    }
    // The page world's __bridgeDefaults is not visible from this world; the app sends them.
    const proposed = new Set(state.defaults || []);
    for (const [key, value] of Object.entries(answers)) {
      markAnswered(key, !proposed.has(key));
      const els = document.querySelectorAll(`[data-record="${CSS.escape(key)}"]`);
      for (const el of els) {
        if (el.classList.contains('color')) color.set(el, String(value));
        else if (el.dataset.value !== undefined) {
          const on = el.dataset.value === String(value);
          el.toggleAttribute('data-selected', on);
          el.setAttribute('aria-pressed', on);
        } else if (el.matches('input[type=checkbox]')) el.checked = value === true;
        else if (el.matches('input[type=radio]')) el.checked = el.value === String(value);
        else if (el.matches('input, select, textarea')) {
          if (el.type === 'select-multiple') for (const o of el.options) o.selected = (value || []).includes(o.value);
          else if (document.activeElement !== el) el.value = value ?? '';
        } else if (el.isContentEditable) { if (document.activeElement !== el) el.textContent = value ?? ''; }
        else {
          for (const input of el.querySelectorAll('input[type=radio], input[type=checkbox]')) {
            input.checked = Array.isArray(value) ? value.includes(input.value) : input.value === String(value);
          }
          const text = el.querySelector('input:not([type=radio]):not([type=checkbox]), textarea');
          if (text && typeof value === 'string' && document.activeElement !== text) text.value = value;
          swatches.mark(el);
        }
      }
    }
  }

  function applyPrevious(previous) {
    for (const el of document.querySelectorAll('.bridge-previous')) el.remove();
    if (!previous) return;
    for (const [key, value] of Object.entries(previous)) {
      if (key in state.answers) continue;
      const els = document.querySelectorAll(`[data-record="${CSS.escape(key)}"]`);
      if (!els.length) continue;
      const last = els[els.length - 1];
      const host = last.closest('.dial') || (last.dataset.value !== undefined && last.parentElement.classList.contains('options') ? last.parentElement : last);
      const hint = document.createElement('span');
      hint.className = 'bridge-previous';
      let text = Array.isArray(value) ? value.join(', ') : String(value);
      if (last.dataset.value !== undefined) {
        const chosen = [...els].find((e) => e.dataset.value === String(value));
        if (chosen) text = (chosen.querySelector('strong, b, h3') || chosen).textContent.trim().split('\n')[0];
      }
      hint.textContent = text;
      host.insertAdjacentElement('afterend', hint);
    }
  }

  function frameRefused(url, why) {
    if (url) state.refused[new URL(url).host] = why;
    for (const el of document.querySelectorAll('.bridge-frame-refused')) el.remove();
    for (const frame of document.querySelectorAll('iframe[src]')) {
      let host;
      try { host = new URL(frame.src).host; } catch { continue; }
      const why = state.refused[host];
      if (!why) continue;
      const notice = document.createElement('p');
      notice.className = 'bridge-frame-refused';
      notice.textContent = `${host} refuses to be shown in a frame (${why}). Present the URL on its own, or serve it through a proxy that drops that header.`;
      frame.insertAdjacentElement('beforebegin', notice);
    }
  }

  function shape() {
    const q = {};
    for (const el of document.querySelectorAll('[data-record]')) {
      const k = el.dataset.record;
      const offered = q[k] || (q[k] = []);
      if (el.classList.contains('color')) offered.push('color');
      else if (el.dataset.value !== undefined) offered.push('=' + el.dataset.value);
      else if (el.matches('select')) offered.push('select:' + [...el.options].map((o) => o.value).join('|'));
      else if (el.matches('input')) offered.push('input:' + el.type + (el.min !== '' ? `:${el.min}-${el.max}` : ''));
      else if (el.matches('textarea') || el.isContentEditable) offered.push('text');
      else offered.push('group:' + [...el.querySelectorAll('input')].map((i) => i.type + '=' + (i.type === 'radio' || i.type === 'checkbox' ? i.value : i.getAttribute('value') || '')).join('|'));
    }
    const api = [];
    let declared = [];
    try { declared = JSON.parse(root.dataset.bridgeDeclare || '[]'); } catch (e) { /* malformed */ }
    for (const k of declared) if (!(k in q)) { q[k] = ['api']; api.push(k); }
    const questions = Object.keys(q).sort();
    return { questions, api, shape: JSON.stringify(questions.map((k) => [k, q[k].sort()])) };
  }

  function setStatus(status) {
    state.status = status;
    root.dataset.bridgeStatus = status;
  }

  function apply(payload) {
    state.answers = payload.answers || {};
    state.defaults = payload.defaults || [];
    state.readOnly = payload.readOnly;
    state.previous = payload.previous;
    setStatus(payload.status);
    root.toggleAttribute('data-bridge-readonly', payload.readOnly);
    applyAnswers(state.answers);
    applyDials();
    applyPrevious(payload.previous);
    frameRefused();
    notes.set(payload.notes || []);
    point(payload.pointing);
    applyDrives();
  }

  function send() {
    if (state.readOnly) return;
    setStatus('sent');
    post('send');
  }

  document.addEventListener('click', (e) => {
    if (state.pointing || e.button !== 0) return;
    if (e.target.closest('.bridge-pin, .bridge-thread')) return;
    const swatch = e.target.closest('.swatches [data-color]');
    if (swatch) { e.preventDefault(); swatches.pick(swatch); return; }
    const option = e.target.closest('[data-record][data-value]:not(.color)');
    if (option) {
      if (!state.readOnly) { select(option); record(option.dataset.record, option.dataset.value); }
      if (option.matches('[data-send]')) { e.preventDefault(); send(); }
      return;
    }
    if (e.target.closest('[data-send]')) { e.preventDefault(); send(); return; }
    const copy = e.target.closest('[data-copy]');
    if (copy) {
      e.preventDefault();
      const source = copy.dataset.copy ? document.querySelector(copy.dataset.copy) : copy.previousElementSibling;
      if (source) {
        const text = source.matches('template') ? source.content.textContent : source.matches('textarea, input') ? source.value : source.innerText;
        navigator.clipboard.writeText(text).then(() => toast('Copied'));
      }
    }
  });

  document.addEventListener('keydown', (e) => {
    const option = e.target.closest?.('[data-record][data-value]');
    if (option && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); option.click(); }
  });

  // In the documented radio card the label wraps only the title, so a click
  // elsewhere on the card would do nothing. Pick the radio unless the click hit
  // a control of the card's own or ended a text selection.
  document.addEventListener('click', (e) => {
    const card = e.target.closest?.('.options > *');
    const radio = card && card.querySelector(':scope > input[type=radio]');
    if (!radio || e.target === radio || e.target.closest('label, a, button, input, select, textarea, [contenteditable]')) return;
    if (getSelection()?.toString()) return;
    if (radio.checked) return;
    radio.checked = true;
    radio.dispatchEvent(new Event('change', { bubbles: true }));
  });

  function onInput(e, delayed) {
    const el = e.target;
    if (ours(el) || el.closest?.('.bridge-thread, .bridge-color')) return;
    if (el.isContentEditable) {
      const host = el.closest('[data-record]');
      if (host) record(host.dataset.record, el.innerText, delayed);
      return;
    }
    if (!el.matches?.('input, select, textarea')) return;
    const own = el.dataset.record;
    if (own) {
      if (el.type === 'radio') { if (el.checked) record(own, el.value); }
      else record(own, valueOf(el), delayed && (el.type === 'text' || el.type === 'search' || el.type === 'url' || el.type === 'email' || el.tagName === 'TEXTAREA' || el.type === 'range' || el.type === 'number'));
      return;
    }
    const group = el.closest('[data-record]');
    if (!group) return;
    if (group.classList.contains('swatches')) {
      const v = el.value.trim();
      if (!/^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(v)) return;
      swatches.mark(group);
      record(group.dataset.record, v, delayed);
      if (group.dataset.drive) drive(group.dataset.drive, v, group.dataset.target, group.dataset.frameTarget);
      return;
    }
    if (el.type === 'radio') { if (el.checked) record(group.dataset.record, el.value); }
    else if (el.type === 'checkbox') {
      const boxes = [...group.querySelectorAll('input[type=checkbox]')];
      record(group.dataset.record, boxes.length === 1 ? el.checked : boxes.filter((i) => i.checked).map((i) => i.value));
    }
    else record(group.dataset.record, valueOf(el), delayed);
  }
  // ---- controls that drive the preview: data-drive="--prop" [data-unit] [data-target]

  function driveValue(el) {
    const unit = el.dataset.unit || '';
    if (!el.matches('input, select, textarea')) {
      const inner = el.querySelector('input:checked, input:not([type=radio]):not([type=checkbox]), select, textarea');
      return (inner ? inner.value : '') + unit;
    }
    return (el.type === 'checkbox' ? (el.checked ? 1 : 0) : el.value) + unit;
  }

  // ---- swatches: buttons with data-color inside a data-record group with a hex field

  const swatches = {
    paint() {
      for (const b of document.querySelectorAll('.swatches [data-color]')) {
        b.style.background = b.dataset.color;
        if (!b.title) b.title = b.dataset.color;
      }
    },
    mark(group) {
      const hex = group.querySelector('input:not([type=radio]):not([type=checkbox])');
      const current = (hex ? hex.value : '').toLowerCase();
      for (const b of group.querySelectorAll('[data-color]')) b.setAttribute('aria-pressed', b.dataset.color.toLowerCase() === current);
    },
    pick(button) {
      const group = button.closest('[data-record]');
      if (!group) return;
      const hex = group.querySelector('input:not([type=radio]):not([type=checkbox])');
      if (hex) hex.value = button.dataset.color;
      swatches.mark(group);
      record(group.dataset.record, button.dataset.color);
      if (group.dataset.drive) drive(group.dataset.drive, button.dataset.color, group.dataset.target, group.dataset.frameTarget);
    },
  };

  // target is a selector in this page; frameTarget one inside embedded sites
  // (their root by default, so the property cascades through the whole site).
  function drive(prop, value, target, frameTarget) {
    for (const el of document.querySelectorAll(target || ':root')) el.style.setProperty(prop, value);
    if (document.querySelector('iframe')) post('drive', { prop, value, target: frameTarget || null });
  }

  function applyDrives() {
    for (const el of document.querySelectorAll('[data-drive]')) {
      if (el.classList.contains('color')) { if (el.dataset.value) drive(el.dataset.drive, el.dataset.value, el.dataset.target, el.dataset.frameTarget); }
      else drive(el.dataset.drive, driveValue(el), el.dataset.target, el.dataset.frameTarget);
    }
  }

  document.addEventListener('bridge:drive', () => {
    try { const { prop, value, target, frameTarget } = JSON.parse(root.dataset.bridgeDrive); drive(prop, value, target, frameTarget); } catch (e) { /* malformed */ }
  });

  document.addEventListener('input', (e) => {
    const wipe = e.target.closest?.('.wipe');
    if (wipe && e.target.type === 'range') { wipe.style.setProperty('--wipe', e.target.value + '%'); return; }
    if (e.target.dataset?.drive) drive(e.target.dataset.drive, driveValue(e.target), e.target.dataset.target, e.target.dataset.frameTarget);
    if (e.target.closest?.('.dial')) dialFill(e.target);
    onInput(e, true);
  });

  // ---- dials: a native range that fills its whole row

  function dialFill(input) {
    const row = input.closest('.dial');
    if (!row || input.type !== 'range') return;
    const min = Number(input.min || 0), max = Number(input.max || 100), v = Number(input.value);
    row.style.setProperty('--fill', (max > min ? ((v - min) / (max - min)) * 100 : 0) + '%');
    const out = row.querySelector('output');
    if (out) out.textContent = input.value + (input.dataset.unit || '');
  }

  function applyDials() {
    for (const input of document.querySelectorAll('.dial input[type=range]')) dialFill(input);
  }

  // ---- colour: OKLCH dials, rendered by the browser, hex and gamut computed here

  const color = {};
  color.toLinear = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  color.toGamma = (c) => (c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055);
  color.fromRgb = (r, g, b) => {
    const [lr, lg, lb] = [r, g, b].map(color.toLinear);
    const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
    const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
    const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
    const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
    const a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
    const b2 = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
    let h = (Math.atan2(b2, a) * 180) / Math.PI; if (h < 0) h += 360;
    return { l: L, c: Math.hypot(a, b2), h };
  };
  color.toLinearRgb = ({ l: L, c, h }) => {
    const a = c * Math.cos((h * Math.PI) / 180), b2 = c * Math.sin((h * Math.PI) / 180);
    const l = (L + 0.3963377774 * a + 0.2158037573 * b2) ** 3;
    const m = (L - 0.1055613458 * a - 0.0638541728 * b2) ** 3;
    const s = (L - 0.0894841775 * a - 1.291485548 * b2) ** 3;
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s, -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s];
  };
  color.inGamut = (lin) => lin.every((v) => v >= -0.0005 && v <= 1.0005);
  color.toP3 = ([r, g, b]) => {
    const x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b, y = 0.2126729 * r + 0.7151522 * g + 0.072175 * b, z = 0.0193339 * r + 0.119192 * g + 0.9503041 * b;
    return [2.493496911941425 * x - 0.9313836179191239 * y - 0.40271078445071684 * z, -0.8294889695615747 * x + 1.7626640603183463 * y + 0.023624685841943577 * z, 0.03584583024378447 * x - 0.07617238926804182 * y + 0.9568845240076872 * z];
  };
  color.hex = (lch) => '#' + color.toLinearRgb(lch).map((v) => Math.round(color.toGamma(Math.min(1, Math.max(0, v))) * 255).toString(16).padStart(2, '0')).join('');
  color.string = ({ l, c, h }) => `oklch(${l.toFixed(3)} ${c.toFixed(3)} ${h.toFixed(1)})`;
  color.parse = (text) => {
    const t = (text || '').trim();
    let m = t.match(/^oklch\(\s*([\d.]+)%?\s+([\d.]+)\s+([\d.]+)/i);
    if (m) { let l = Number(m[1]); if (t.includes('%')) l /= 100; return { l, c: Number(m[2]), h: Number(m[3]) }; }
    m = t.match(/^#?([0-9a-f]{3}|[0-9a-f]{6})$/i);
    if (m) {
      let hx = m[1]; if (hx.length === 3) hx = [...hx].map((ch) => ch + ch).join('');
      return color.fromRgb(...[0, 2, 4].map((i) => parseInt(hx.slice(i, i + 2), 16) / 255));
    }
    return null;
  };
  color.gamut = (lch) => {
    const lin = color.toLinearRgb(lch);
    return color.inGamut(lin) ? 'sRGB' : color.inGamut(color.toP3(lin)) ? 'P3' : 'out of gamut';
  };

  color.build = function (host) {
    if (host.querySelector('.bridge-color')) return;
    const dial = (name, label, min, max, step) =>
      `<label class="dial bridge-color-dial"><span>${label}</span><input type="range" name="${name}" min="${min}" max="${max}" step="${step}"><output></output></label>`;
    host.innerHTML = `<div class="bridge-color"><div class="bridge-swatch"></div><div class="bridge-color-dials">${dial('l', 'Lightness', 0, 1, 0.001)}${dial('c', 'Chroma', 0, 0.4, 0.001)}${dial('h', 'Hue', 0, 360, 0.1)}</div><div class="bridge-color-read"><input class="bridge-hex" type="text" spellcheck="false" aria-label="Hex"><code></code><small></small></div></div>`;
    host.dataset.enhanced = '';
    host.addEventListener('input', (e) => {
      if (e.target.type !== 'range') return;
      color.render(host);
      color.commit(host);
    });
    host.querySelector('.bridge-hex').addEventListener('change', (e) => {
      const lch = color.parse(e.target.value);
      if (lch) { color.set(host, color.string(lch)); color.commit(host); }
    });
    color.set(host, host.getAttribute('value') || 'oklch(0.7 0.12 250)');
  };

  color.set = function (host, text) {
    if (!host.querySelector('.bridge-color')) color.build(host);
    const lch = color.parse(text);
    if (!lch) return;
    for (const [k, v] of Object.entries(lch)) host.querySelector(`input[name=${k}]`).value = v;
    color.render(host);
  };

  color.current = (host) => ({ l: Number(host.querySelector('input[name=l]').value), c: Number(host.querySelector('input[name=c]').value), h: Number(host.querySelector('input[name=h]').value) });

  color.render = function (host) {
    const lch = color.current(host);
    const css = color.string(lch);
    host.querySelector('.bridge-swatch').style.background = css;
    host.querySelector('.bridge-color-read code').textContent = css;
    host.querySelector('.bridge-color-read small').textContent = color.gamut(lch);
    const hex = host.querySelector('.bridge-hex');
    if (document.activeElement !== hex) hex.value = color.hex(lch);
    host.querySelector('input[name=h]').closest('.dial').style.setProperty('--dial-l', lch.l);
    host.querySelector('input[name=h]').closest('.dial').style.setProperty('--dial-c', lch.c);
    host.querySelector('input[name=c]').closest('.dial').style.setProperty('--dial-l', lch.l);
    host.querySelector('input[name=c]').closest('.dial').style.setProperty('--dial-h', lch.h);
    host.querySelector('input[name=l]').closest('.dial').style.setProperty('--dial-h', lch.h);
    host.dataset.value = css;
    for (const input of host.querySelectorAll('.dial input')) dialFill(input);
  };

  color.commit = function (host) {
    const css = host.dataset.value;
    if (host.dataset.record) record(host.dataset.record, css);
    if (host.dataset.drive) drive(host.dataset.drive, css, host.dataset.target, host.dataset.frameTarget);
  };

  function enhance() {
    for (const host of document.querySelectorAll('.color')) color.build(host);
    swatches.paint();
  }
  document.addEventListener('change', (e) => onInput(e, false));

  // ---- live patching

  function scriptSignature(doc) {
    return JSON.stringify([...doc.querySelectorAll('script')].filter((s) => !ours(s)).map((s) => s.src || s.textContent));
  }
  let currentScripts = null;

  const morphCallbacks = {
    beforeNodeRemoved: (node) => !ours(node),
    beforeNodeMorphed: (node) => !ours(node),
  };

  function highlight() {
    if (typeof Prism === 'undefined') return;
    for (const code of document.querySelectorAll('code[class*="language-"]')) {
      if (code.dataset.highlighted === code.textContent) continue;
      const source = code.textContent;
      try { Prism.highlightElement(code, false); } catch (e) { /* an unknown grammar leaves the code plain */ }
      code.dataset.highlighted = source;
    }
  }

  function renderMarkdown() {
    const source = document.getElementById('markdown-source');
    const host = document.querySelector('.bridge-md');
    if (!source || !host || typeof marked === 'undefined') return;
    host.innerHTML = marked.parse(source.content.textContent);
  }

  // Elements a page owes to its markup, not to a script: everything except the
  // runtime's furniture, Prism's tokens and rendered markdown.
  function structure(root) {
    let n = 0;
    const walk = (el) => {
      for (const child of el.children) {
        if (ours(child)) continue;
        n += 1;
        if (child.matches('code[class*="language-"]')) continue;
        walk(child);
      }
    };
    if (root) walk(root);
    return n;
  }

  async function patch(html, previous) {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    if (currentScripts === null) currentScripts = scriptSignature(document);
    if (scriptSignature(doc) !== currentScripts) return { reload: true, reason: 'scripts' };
    // A page that renders itself from a script has structure the file does not
    // hold; a morph would delete it and nothing would put it back.
    if (typeof previous === 'string' && document.querySelector('script:not([src])')) {
      const was = new DOMParser().parseFromString(previous, 'text/html');
      if (structure(document.body) !== structure(was.body)) return { reload: true, reason: 'script-built' };
    }
    for (const our of document.querySelectorAll('.bridge-thread:popover-open')) notes.keepOpen = our.dataset.id;
    Idiomorph.morph(document.head, doc.head, { morphStyle: 'innerHTML', callbacks: morphCallbacks });
    Idiomorph.morph(document.body, doc.body, { morphStyle: 'outerHTML', ignoreActiveValue: true, callbacks: morphCallbacks });
    document.title = doc.title;
    state.patches += 1;
    renderMarkdown();
    highlight();
    enhance();
    applyAnswers(state.answers);
    const s = shape();
    const payload = await post('shape', s);
    apply(payload);
    notes.place();
    return { reload: false };
  }

  // ---- point, pins, notes

  function cssPath(el) {
    const parts = [];
    let node = el;
    while (node && node !== document.body && parts.length < 6) {
      if (node.id) { parts.unshift('#' + CSS.escape(node.id)); break; }
      let part = node.localName;
      const classes = [...node.classList].filter((c) => !c.startsWith('bridge-')).slice(0, 3);
      if (classes.length) part += '.' + classes.map(CSS.escape).join('.');
      const same = [...node.parentElement.children].filter((c) => c.localName === node.localName);
      if (same.length > 1) part += `:nth-of-type(${same.indexOf(node) + 1})`;
      parts.unshift(part);
      node = node.parentElement;
    }
    return parts.join(' > ');
  }

  function describe(el, x, y) {
    const rect = el.getBoundingClientRect();
    const classes = [...el.classList].filter((c) => !c.startsWith('bridge-'));
    const same = [...el.parentElement.children].filter((c) => c.localName === el.localName);
    const text = (el.innerText || el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 80);
    const frac = (v) => (Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 0.5);
    const anchor = {
      selector: cssPath(el), tag: el.localName, classes, index: same.indexOf(el), text,
      x: frac(rect.width ? (x - rect.left) / rect.width : 0.5), y: frac(rect.height ? (y - rect.top) / rect.height : 0.5),
    };
    const short = text.length > 40 ? text.slice(0, 40) + '…' : text;
    let target = el.localName + (classes.length ? '.' + classes.join('.') : '') + (short ? ` "${short}"` : '');
    if (!short) {
      const name = el.getAttribute('alt') || el.getAttribute('src')?.split('/').pop() || el.id;
      target += (name ? ` "${name}"` : '') + ` @ ${Math.round(anchor.x * 100)}%, ${Math.round(anchor.y * 100)}%`;
    }
    return { anchor, target };
  }

  function sameText(el, text) {
    if (!text) return true;
    const now = (el.innerText || el.textContent || '').trim().replace(/\s+/g, ' ');
    return now.startsWith(text.slice(0, 30));
  }

  function resolve(anchor) {
    if (!anchor || !anchor.tag) return null;
    try {
      const hit = document.querySelector(anchor.selector);
      if (hit && hit.localName === anchor.tag && sameText(hit, anchor.text)) return hit;
    } catch (e) { /* selector no longer parses */ }
    const candidates = [...document.getElementsByTagName(anchor.tag)].filter((el) =>
      !ours(el) && (anchor.classes || []).every((c) => el.classList.contains(c)) && sameText(el, anchor.text));
    if (!candidates.length) return null;
    return candidates.find((el) => [...el.parentElement.children].filter((c) => c.localName === el.localName).indexOf(el) === anchor.index) || candidates[0];
  }

  const notes = { list: [], pins: new Map(), drafts: {}, keepOpen: null, pending: null };

  notes.set = function (list) {
    notes.list = list;
    state.notes = list;
    const ids = new Set(list.map((n) => n.id));
    for (const [id, pin] of notes.pins) if (!ids.has(id) && id !== notes.pending?.id) { pin.remove(); notes.pins.delete(id); notes.thread(id)?.remove(); }
    let n = 0;
    for (const note of list) {
      n += 1;
      let pin = notes.pins.get(note.id);
      if (!pin) {
        pin = document.createElement('button');
        pin.className = 'bridge-pin';
        pin.setAttribute('popover', 'manual');
        pin.dataset.id = note.id;
        pin.style.anchorName = `--bridge-pin-${note.id}`;
        pin.addEventListener('click', () => { if (!pin.dataset.dragged) notes.toggle(note.id); });
        notes.draggable(pin, note.id);
        root.appendChild(pin);
        notes.pins.set(note.id, pin);
      }
      pin.dataset.n = n;
      pin.dataset.state = note.state;
      pin.title = note.text;
    }
    notes.place();
    const open = document.querySelector('.bridge-thread:popover-open');
    if (open) notes.render(open.dataset.id);
  };

  notes.place = function () {
    const anchored = new Map();
    let lost = 0;
    for (const [id, pin] of notes.pins) {
      const note = notes.list.find((x) => x.id === id) || (notes.pending?.id === id ? notes.pending : null);
      const el = note && resolve(note.anchor);
      if (el) {
        const names = anchored.get(el) || [];
        names.push(`--bridge-at-${id}`);
        anchored.set(el, names);
        pin.removeAttribute('data-lost');
        pin.style.pointerEvents = '';
        pin.style.positionAnchor = `--bridge-at-${id}`;
        pin.style.left = `calc(anchor(left) + anchor-size(width) * ${note.anchor.x ?? 0.5})`;
        pin.style.top = `calc(anchor(top) + anchor-size(height) * ${note.anchor.y ?? 0.5})`;
        pin.style.removeProperty('right');
      } else {
        pin.setAttribute('data-lost', '');
        pin.style.positionAnchor = 'none';
        pin.style.left = 'auto';
        pin.style.top = `${52 + lost * 30}px`;
        lost += 1;
      }
      if (!pin.matches(':popover-open')) pin.showPopover();
      const thread = notes.thread(id);
      if (thread) {
        thread.querySelector('.bridge-lost')?.remove();
        if (!el) thread.insertAdjacentHTML('afterbegin', '<div class="bridge-lost">Pointing at nothing now</div>');
      }
    }
    for (const el of document.querySelectorAll('[style*="--bridge-at-"]')) if (!anchored.has(el) && !ours(el)) el.style.removeProperty('anchor-name');
    for (const [el, names] of anchored) el.style.anchorName = names.join(', ');
    const lostNow = {};
    for (const note of notes.list) lostNow[note.id] = notes.pins.get(note.id)?.hasAttribute('data-lost') === true;
    const changed = notes.list.some((n) => (n.lost === true) !== lostNow[n.id]);
    if (changed) { for (const n of notes.list) n.lost = lostNow[n.id]; post('lost', { lost: lostNow }); }
  };

  // A press that moves under a few pixels is a click; past that it is a drag
  // that re-anchors the pin to the element it lands on.
  notes.draggable = function (pin, id) {
    let start = null;
    pin.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      start = { x: e.clientX, y: e.clientY, moved: false };
      delete pin.dataset.dragged;
      try { pin.setPointerCapture(e.pointerId); } catch (err) { /* synthetic pointer */ }
    });
    pin.addEventListener('pointermove', (e) => {
      if (!start) return;
      if (!start.moved && Math.hypot(e.clientX - start.x, e.clientY - start.y) < 4) return;
      start.moved = true;
      pin.dataset.dragged = '1';
      pin.style.positionAnchor = 'none';
      pin.style.left = e.clientX + 'px';
      pin.style.top = e.clientY + 'px';
      pin.style.pointerEvents = 'none';
    });
    const finish = (e) => {
      if (!start) return;
      const moved = start.moved;
      start = null;
      if (!moved) return;
      // The pin sits under the pointer, so hit-test before it takes hits again.
      const under = document.elementFromPoint(e.clientX, e.clientY);
      pin.style.pointerEvents = '';
      const target = under && !ours(under) && !under.closest('.bridge-pin, .bridge-thread') ? under : null;
      if (target) notes.move(id, target, e.clientX, e.clientY); else notes.place();
      setTimeout(() => delete pin.dataset.dragged, 0);
    };
    pin.addEventListener('pointerup', finish);
    pin.addEventListener('pointercancel', finish);
  };

  notes.move = async function (id, el, x, y) {
    const { anchor, target } = describe(el, x, y);
    if (notes.pending && notes.pending.id === id) {
      Object.assign(notes.pending, { anchor, target });
      notes.place();
      notes.render(id);
      return;
    }
    const list = await post('note', { id, action: 'move', anchor, target });
    notes.set(list);
    notes.render(id);
  };

  notes.thread = (id) => document.querySelector(`.bridge-thread[data-id="${CSS.escape(id)}"]`);

  notes.toggle = function (id) {
    const existing = notes.thread(id);
    if (existing && existing.matches(':popover-open')) { existing.hidePopover(); return; }
    notes.open(id);
  };

  notes.open = function (id) {
    for (const t of document.querySelectorAll('.bridge-thread:popover-open')) if (t.dataset.id !== id) t.hidePopover();
    let thread = notes.thread(id);
    if (!thread) {
      thread = document.createElement('div');
      thread.className = 'bridge-thread';
      thread.setAttribute('popover', 'auto');
      thread.dataset.id = id;
      thread.style.positionAnchor = `--bridge-pin-${id}`;
      thread.addEventListener('toggle', (e) => {
        notes.pins.get(id)?.toggleAttribute('data-open', e.newState === 'open');
        if (e.newState === 'closed') {
          const draft = thread.querySelector('textarea');
          if (draft) notes.drafts[id] = draft.value;
          if (id === notes.pending?.id && !notes.drafts[id]) notes.cancelPending();
        }
      });
      root.appendChild(thread);
    }
    notes.render(id);
    thread.showPopover();
    const box = thread.querySelector('textarea');
    if (box) { box.focus(); box.setSelectionRange(box.value.length, box.value.length); }
  };

  notes.render = function (id) {
    const thread = notes.thread(id);
    if (!thread) return;
    const before = thread.querySelector('textarea');
    const hadFocus = before && document.activeElement === before;
    if (before) notes.drafts[id] = before.value;
    const note = notes.list.find((x) => x.id === id);
    const pending = notes.pending && notes.pending.id === id ? notes.pending : null;
    const target = note ? note.target : pending ? pending.target : '';
    const esc = (t) => t.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
    // No location line: the user is looking at the pinned element. The record
    // keeps the target for the agent, which has no screen. Lost still shows: it
    // is a state of the thread, not a location.
    let html = notes.pins.get(id)?.hasAttribute('data-lost') ? '<div class="bridge-lost">Pointing at nothing now</div>' : '';
    if (note) {
      html += `<div class="bridge-say"><b>You</b>${esc(note.text)}</div>`;
      for (const say of note.said) {
        html += say.kind === 'status' ? `<div class="bridge-say" data-kind="status">${esc(say.text)}</div>`
          : `<div class="bridge-say"><b>${say.by === 'agent' ? 'Agent' : 'You'}</b>${esc(say.text)}</div>`;
      }
    }
    const draft = notes.drafts[id] || '';
    html += `<textarea placeholder="${note ? 'Reply' : 'What should change here?'}" rows="2">${esc(draft)}</textarea>`;
    html += '<div class="bridge-bar"><span>⌘⏎</span>';
    if (note) {
      html += `<button data-act="delete">Delete</button>`;
      html += `<button data-act="${note.state === 'done' ? 'reopen' : 'done'}">${note.state === 'done' ? 'Reopen' : 'Done'}</button>`;
      html += `<button data-act="reply" class="bridge-primary">Reply</button>`;
    } else {
      html += `<button data-act="cancel">Cancel</button><button data-act="save" class="bridge-primary">Save</button>`;
    }
    html += '</div>';
    thread.innerHTML = html;
    const box = thread.querySelector('textarea');
    box.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && e.metaKey) { e.preventDefault(); notes.act(id, note ? 'reply' : 'save'); }
      if (e.key === 'Escape') { e.preventDefault(); thread.hidePopover(); }
    });
    thread.querySelectorAll('button').forEach((b) => b.addEventListener('click', () => notes.act(id, b.dataset.act)));
    if (hadFocus) { box.focus(); box.setSelectionRange(box.value.length, box.value.length); }
  };

  notes.act = async function (id, action) {
    const thread = notes.thread(id);
    const text = (thread?.querySelector('textarea')?.value || '').trim();
    if (action === 'cancel') { notes.drafts[id] = ''; thread.hidePopover(); notes.cancelPending(); return; }
    if (action === 'save') {
      if (!text) return;
      const pending = notes.pending;
      const reply = await post('pin', { anchor: pending.anchor, target: pending.target, text });
      notes.drafts[id] = '';
      thread.hidePopover();
      thread.remove();
      notes.pins.get(id)?.remove();
      notes.pins.delete(id);
      notes.pending = null;
      notes.set(reply.notes);
      return;
    }
    if (action === 'reply' && !text) return;
    const list = await post('note', { id, action, text });
    // render() keeps the box's contents as the draft, so a filed reply left in
    // it would look unsent and a second press would file it twice.
    const box = thread?.querySelector('textarea');
    if (box) box.value = '';
    notes.drafts[id] = '';
    if (action === 'delete') { thread.hidePopover(); notes.set(list); return; }
    notes.set(list);
    notes.render(id);
  };

  notes.cancelPending = function () {
    const p = notes.pending;
    if (!p) return;
    notes.pins.get(p.id)?.remove();
    notes.pins.delete(p.id);
    notes.thread(p.id)?.remove();
    notes.pending = null;
    notes.place();
  };

  notes.reveal = function (id) {
    const note = notes.list.find((x) => x.id === id);
    const el = note && resolve(note.anchor);
    if (el) el.scrollIntoView({ block: 'center' });
    notes.open(id);
  };

  function pointAt(e) {
    const target = e.target.closest?.('*');
    if (!target || ours(target) || target.closest('.bridge-pin, .bridge-thread')) return;
    e.preventDefault();
    e.stopPropagation();
    point(false);
    post('pointing', { on: false });
    notes.cancelPending();
    const id = 'new-' + Date.now();
    const { anchor, target: label } = describe(target, e.clientX, e.clientY);
    notes.pending = { id, anchor, target: label };
    const pin = document.createElement('button');
    pin.className = 'bridge-pin';
    pin.setAttribute('popover', 'manual');
    pin.dataset.id = id;
    pin.dataset.n = '+';
    pin.style.anchorName = `--bridge-pin-${id}`;
    pin.addEventListener('click', () => { if (!pin.dataset.dragged) notes.toggle(id); });
    notes.draggable(pin, id);
    root.appendChild(pin);
    notes.pins.set(id, pin);
    notes.place();
    notes.open(id);
  }
  document.addEventListener('click', (e) => { if (state.pointing) pointAt(e); }, true);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && state.pointing) { point(false); post('pointing', { on: false }); } });

  // While pointing, a pin follows the cursor with its tip on the pointer, to
  // show where it will land before the click.
  let ghost = null;
  function ghostMove(e) { if (ghost) { ghost.style.left = e.clientX + 'px'; ghost.style.top = e.clientY + 'px'; } }
  function point(on) {
    state.pointing = !!on && !state.readOnly;
    root.toggleAttribute('data-bridge-pointing', state.pointing);
    if (state.pointing && !ghost) {
      ghost = document.createElement('div');
      ghost.className = 'bridge-pin bridge-ghost';
      ghost.dataset.n = '+';
      ghost.style.left = '-100px';
      ghost.style.top = '-100px';
      root.appendChild(ghost);
      document.addEventListener('pointermove', ghostMove, true);
    } else if (!state.pointing && ghost) {
      ghost.remove();
      ghost = null;
      document.removeEventListener('pointermove', ghostMove, true);
    }
  }

  let toastTimer;
  function toast(text) {
    let el = document.querySelector('.bridge-toast');
    if (!el) { el = document.createElement('div'); el.className = 'bridge-toast'; root.appendChild(el); }
    el.textContent = text;
    el.style.opacity = 1;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.style.opacity = 0; }, 1200);
  }

  function setData(json) {
    root.dataset.bridgeData = json;
    document.dispatchEvent(new Event('bridge:data'));
  }

  // Keys a page's script touches through bridge.get/set: questions without a control.
  document.addEventListener('bridge:declare', async () => {
    if (started && !state.readOnly) apply(await post('shape', shape()));
  });
  document.addEventListener('bridge:record', () => {
    try {
      const { key, value } = JSON.parse(root.dataset.bridgeRecord);
      record(key, value, true);
    } catch (e) { /* malformed */ }
  });
  document.addEventListener('bridge:send', send);
  document.addEventListener('bridge:error', () => post('error', { text: root.dataset.bridgeError }));
  document.addEventListener('bridge:rendered', async () => {
    if (!started) { ready(); return; }
    const payload = await post('shape', shape());
    apply(payload);
    notes.place();
  });

  globalThis.__bridge = {
    patch,
    status: setStatus,
    point,
    notes: (list) => notes.set(list),
    reveal: (id) => notes.reveal(id),
    state,
    shape,
    setData,
    drive,
    applyDrives,
    frameRefused,
  };
  globalThis.__bridgeNotes = notes;

  // Reports class tokens no stylesheet defines, which an agent otherwise guesses
  // at without noticing, and classes both the kit and the page define, which
  // look styled but mix two meanings. The CLI prints both on stderr.
  function auditClasses() {
    if (options.built || !options.local) return { unknown: [], both: [] };
    const kit = new Set(), page = new Set();
    const note = (text, into) => { for (const m of text.matchAll(/\.(-?[_a-zA-Z][\w-]*)/g)) into.add(m[1]); };
    note(__BRIDGE_CSS.page, kit);
    const walk = (rules) => { for (const r of rules) { if (r.selectorText) note(r.selectorText, page); if (r.cssRules) walk(r.cssRules); } };
    for (const sheet of document.styleSheets) {
      if (ours(sheet.ownerNode)) continue;
      // A sheet this page loads from elsewhere cannot be read; it may define anything, so nothing is unknown.
      try { walk(sheet.cssRules); } catch { return { unknown: [], both: [] }; }
    }
    const unknown = new Set(), both = new Set();
    for (const el of document.querySelectorAll('[class]')) {
      if (ours(el) || el.classList.contains('token') || el.closest('[class*="bridge-"]')) continue;
      for (const c of el.classList) {
        if (c === 'token' || c.startsWith('language-') || c.startsWith('bridge-')) continue;
        if (kit.has(c) && page.has(c)) both.add(c);
        else if (!kit.has(c) && !page.has(c)) unknown.add(c);
      }
    }
    return { unknown: [...unknown], both: [...both] };
  }

  // A control that shows a value from its markup (a checked radio, a checkbox,
  // a range, a select) is recorded as a default, so the record matches what the
  // page shows: clicking an already-checked radio fires nothing. Answered keys
  // and read-only pages are left alone.
  function recordDefaults(answers) {
    if (state.readOnly) return;
    // A proposal, not an answer: it does not reopen a sent page, and the record names it as a default.
    const propose = (key, value) => { state.answers[key] = value; post('record', { key, value, default: true }); };
    const done = new Set(Object.keys(answers));
    for (const el of document.querySelectorAll('input[data-record], select[data-record], textarea[data-record]')) {
      const key = el.dataset.record;
      if (done.has(key) || ours(el)) continue;
      let value;
      if (el.type === 'radio') { if (!el.checked) continue; value = el.value; }
      else if (el.type === 'checkbox') value = el.checked;
      else if (el.type === 'range' || el.type === 'number') { if (el.value === '') continue; value = valueOf(el); }
      else { if (!el.value) continue; value = valueOf(el); }
      done.add(key);
      propose(key, value);
    }
    for (const group of document.querySelectorAll('[data-record]:not(input):not(select):not(textarea):not([data-value]):not(.color):not(.swatches)')) {
      const key = group.dataset.record;
      if (done.has(key) || ours(group)) continue;
      const boxes = [...group.querySelectorAll('input[type=checkbox]')];
      const radio = group.querySelector('input[type=radio]:checked');
      if (radio) { done.add(key); propose(key, radio.value); }
      else if (boxes.length) { done.add(key); propose(key, boxes.length === 1 ? boxes[0].checked : boxes.filter((i) => i.checked).map((i) => i.value)); }
    }
  }

  let started = false;
  async function ready() {
    if (started) return;
    started = true;
    currentScripts = scriptSignature(document);
    renderMarkdown();
    highlight();
    enhance();
    const picture = document.querySelector('.doc-image img');
    if (picture) {
      const report = () => post('size', { width: picture.naturalWidth, height: picture.naturalHeight });
      if (picture.complete && picture.naturalWidth) report(); else picture.addEventListener('load', report, { once: true });
    }
    const payload = await post('ready', { title: document.title, classes: auditClasses(), ...shape() });
    apply(payload);
    recordDefaults(payload.answers || {});
  }
  // A page using bridge.ready() restores itself in its callbacks; hash it after
  // that, so the keys it read are questions from the first fingerprint on.
  const readyAfterPage = () => {
    if (root.dataset.bridgeApi === '1' && root.dataset.bridgePageReady !== '1') document.addEventListener('bridge:page-ready', ready, { once: true });
    else ready();
  };
  if (options.built) setTimeout(ready, 1500);
  else if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', readyAfterPage);
  else readyAfterPage();
}
