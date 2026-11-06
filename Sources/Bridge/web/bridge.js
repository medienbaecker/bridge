function __bridgeInit(options) {
  if (globalThis.__bridge) return;
  const handler = window.webkit.messageHandlers.bridge;
  const post = (type, data = {}) => handler.postMessage({ type, ...data });

  // A frame from another origin cannot read its own iframe element, so it asks
  // the frame around it for its data-links.
  window.addEventListener('message', (e) => {
    if (e.data?.bridgeLinks !== '?') return;
    const frame = [...document.querySelectorAll('iframe')].find((f) => f.contentWindow === e.source);
    if (frame) e.source.postMessage({ bridgeLinks: frame.dataset.links || 'external' }, '*');
  });

  // Inside an embedded frame (a live site in an iframe) the runtime only
  // receives driven CSS properties; everything else belongs to the top page.
  if (window !== window.top) {
    window.addEventListener('message', (e) => {
      if (e.source === window.parent && e.data?.bridgeLinks && e.data.bridgeLinks !== '?') post('frame-links', { links: e.data.bridgeLinks });
    });
    window.parent.postMessage({ bridgeLinks: '?' }, '*');
    globalThis.__bridge = {
      drive(prop, value, target) {
        for (const el of document.querySelectorAll(target || ':root')) el.style.setProperty(prop, value);
      },
    };
    const announce = () => post('frame-ready', { url: location.href });
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', announce); else announce();
    return;
  }
  const state = { answers: {}, proposed: {}, status: 'open', readOnly: false, previous: null, timers: {}, patches: 0, refused: {} };
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
      for (const label of el.labels || []) {
        if (label.classList.contains('dial')) continue;
        label.querySelector(':scope .bridge-answered-dot')?.remove();
        if (!on) continue;
        const dot = document.createElement('span');
        dot.className = 'bridge-answered-dot';
        if (el.tagName === 'TEXTAREA' && label.contains(el)) el.before(dot); else label.append(dot);
      }
      (el.closest('.dial') || el).title = on ? 'Your answer' : '';
    }
  }

  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const empty = (v) => v === '' || v === null || v === undefined || (Array.isArray(v) && !v.length);

  function record(key, value, delay, fromScript) {
    if (state.readOnly) return;
    const proposed = state.proposed || {};
    if (!fromScript && (key in proposed ? same(value, proposed[key]) : empty(value))) { clear(key); return; }
    state.answers[key] = value;
    markAnswered(key, true);
    markDefaults();
    if (state.status === 'sent') setStatus('open');
    clearTimeout(state.timers[key]);
    if (delay) state.timers[key] = setTimeout(() => post('record', { key, value }), 150);
    else post('record', { key, value });
  }

  function clear(key) {
    clearTimeout(state.timers[key]);
    if (state.readOnly || !(key in state.answers)) return;
    delete state.answers[key];
    markAnswered(key, false);
    markDefaults();
    if (state.status === 'sent') setStatus('open');
    post('record', { key, clear: true });
  }

  const labelOf = (input) => (input.id && document.querySelector(`label[for="${CSS.escape(input.id)}"]`)) || input.closest('label');

  function markDefaults() {
    for (const t of document.querySelectorAll('bridge-default')) t.remove();
    for (const el of document.querySelectorAll('[data-default], [data-default-tag]')) { el.removeAttribute('data-default'); el.removeAttribute('data-default-tag'); }
    if (state.readOnly) return;
    const tag = (after, inside) => {
      if (inside) { after.setAttribute('data-default-tag', ''); return; }
      const t = document.createElement('bridge-default');
      t.className = 'bridge-default';
      t.textContent = 'default';
      t.title = "The page's value; you have not changed it";
      after.insertAdjacentElement('afterend', t);
    };
    for (const key of Object.keys(state.proposed || {})) {
      if (key in state.answers) continue;
      for (const el of document.querySelectorAll(`[data-record="${CSS.escape(key)}"]`)) {
        if (ours(el)) continue;
        const dial = el.closest('.dial');
        if (dial) dial.setAttribute('data-default', '');
        else if (el.matches('input[type=radio], input[type=checkbox]')) { if (el.type === 'checkbox' || el.checked) { const label = labelOf(el); if (label) tag(label, true); else tag(el); } }
        else if (el.matches('input, select, textarea, .color')) { el.setAttribute('data-default', ''); tag(el); }
        else {
          const radio = el.querySelector('input[type=radio]:checked');
          if (radio) { const label = labelOf(radio); if (label) tag(label, true); else tag(radio); }
          else if (el.querySelector('input[type=checkbox]')) { const legend = el.querySelector('legend'); tag(legend || el, true); }
        }
      }
    }
  }

  function unanswerRadio(radio) {
    const key = radio.dataset.record || radio.closest('[data-record]')?.dataset.record;
    if (!key || state.readOnly || !(key in state.answers)) return;
    radio.checked = false;
    const proposed = (state.proposed || {})[key];
    if (proposed !== undefined && radio.name) {
      for (const other of document.querySelectorAll(`input[type=radio][name="${CSS.escape(radio.name)}"]`)) other.checked = other.value === String(proposed);
    }
    clear(key);
  }

  function select(el, key = el.dataset.record) {
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
    for (const [key, value] of Object.entries(answers)) {
      markAnswered(key, true);
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
    state.proposed = payload.proposed || {};
    state.readOnly = payload.readOnly;
    state.previous = payload.previous;
    setStatus(payload.status);
    root.toggleAttribute('data-bridge-readonly', payload.readOnly);
    applyAnswers(state.answers);
    markDefaults();
    applyDials();
    applyPrevious(payload.previous);
    frameRefused();
    applyDrives();
  }

  function send() {
    if (state.readOnly) return;
    setStatus('sent');
    post('send');
  }

  document.addEventListener('click', (e) => {
    if (e.button !== 0) return;
    const swatch = e.target.closest('.swatches [data-color]');
    if (swatch) { e.preventDefault(); swatches.pick(swatch); return; }
    const option = e.target.closest('[data-record][data-value]:not(.color)');
    if (option) {
      if (!state.readOnly) {
        const key = option.dataset.record;
        if (option.hasAttribute('data-selected') && key in state.answers && !option.matches('[data-send]')) { select(null, key); clear(key); }
        else { select(option); record(key, option.dataset.value); }
      }
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
    if (radio.checked) { unanswerRadio(radio); return; }
    radio.checked = true;
    radio.dispatchEvent(new Event('change', { bubbles: true }));
  });

  let pressedRadio = null;
  document.addEventListener('pointerdown', (e) => {
    const label = e.target.closest?.('label');
    const radio = e.target.matches?.('input[type=radio]') ? e.target : label?.control?.type === 'radio' ? label.control : null;
    pressedRadio = radio && radio.checked ? radio : null;
  }, true);
  document.addEventListener('click', (e) => {
    if (!e.target.matches?.('input[type=radio]') || e.target !== pressedRadio) return;
    pressedRadio = null;
    unanswerRadio(e.target);
  });

  function onInput(e, delayed) {
    const el = e.target;
    if (ours(el) || el.closest?.('.bridge-composer, .bridge-color')) return;
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
    host.innerHTML = marked.parse(source.content.textContent, { renderer: quoteRenderer });
  }

  // ---- quotes: code blocks that show lines from a real file

  const quoted = new Map();
  const quoteErrors = new Set();
  const quoteRenderer = typeof marked === 'undefined' ? null : Object.assign(new marked.Renderer(), {
    code(token) {
      const m = /\b(quote|quoted)=(\S+)/.exec(token.lang || '');
      if (!m) return marked.Renderer.prototype.code.call(this, token);
      const code = document.createElement('code');
      const lang = (token.lang || '').match(/^\S*/)[0];
      if (lang && !lang.includes('=')) code.className = 'language-' + lang;
      code.setAttribute(m[1] === 'quote' ? 'data-quote' : 'data-quoted', m[2]);
      code.textContent = m[1] === 'quote' ? (quoted.get(m[2]) ?? '') : token.text;
      return `<pre>${code.outerHTML}</pre>\n`;
    },
  });

  function fillQuote(code, text) {
    if (code.textContent === text) return false;
    code.textContent = text;
    return true;
  }

  function quotes() {
    const codes = [...document.querySelectorAll('code[data-quote]')];
    for (const code of codes) if (quoted.has(code.dataset.quote)) fillQuote(code, quoted.get(code.dataset.quote));
    return Promise.all(codes.map(async (code) => {
      const spec = code.dataset.quote;
      const reply = await post('quote', { spec });
      const text = reply?.error ?? reply?.text ?? '';
      if (reply?.error && !quoteErrors.has(spec + text)) { quoteErrors.add(spec + text); post('error', { text: `quote ${spec}: ${text}` }); }
      quoted.set(spec, text);
      if (fillQuote(code, text)) highlight();
    }));
  }

  // ---- diagrams: mermaid blocks, drawn by Pele next to their source

  const diagramErrors = new Set();
  const mounted = new WeakMap();
  let loading;

  async function diagrams() {
    if (document.querySelector('pre > code.language-mermaid')) loading ||= post('pele').then(() => globalThis.pele);
    const sources = new Set();
    for (const code of document.querySelectorAll('pre > code.language-mermaid')) {
      const pre = code.parentElement;
      if (ours(pre) || pre.closest('[class*="bridge-"]:not(.bridge-md)')) continue;
      sources.add(pre);
    }
    for (const figure of document.querySelectorAll('.bridge-diagram')) if (!sources.has(figure.previousElementSibling)) figure.remove();
    if (!sources.size) return;
    const { mount, parse } = await loading;
    const onError = (e) => {
      const message = `diagram: ${e.message}`;
      if (!diagramErrors.has(message)) { diagramErrors.add(message); post('error', { text: message }); }
    };
    for (const pre of sources) {
      if (!pre.isConnected) continue;
      const source = pre.textContent;
      let figure = pre.nextElementSibling;
      if (!figure?.classList.contains('bridge-diagram')) {
        figure = document.createElement('figure');
        figure.className = 'bridge-diagram';
        pre.after(figure);
      }
      const diagram = mounted.get(figure);
      if (diagram?.source === source) continue;
      try { parse(source); } catch (e) { onError(e); }
      if (!diagram) mounted.set(figure, mount(figure, source, { onError, zoom: { controls: false } }));
      else diagram.update(source, { onError, zoom: { controls: false } });
    }
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

  // ---- media: local images re-fetched when their file changes

  const mediaAttributes = [['img, video, audio, source', 'src'], ['video', 'poster']];
  const mediaVersions = {};

  function mediaPath(url) {
    try {
      const u = new URL(url, document.baseURI);
      return u.protocol === 'file:' || u.protocol === 'bridge-file:' ? decodeURIComponent(u.pathname) : null;
    } catch (e) { return null; }
  }

  function eachMedia(fn) {
    for (const [selector, attr] of mediaAttributes) {
      for (const el of document.querySelectorAll(selector)) {
        const value = el.getAttribute(attr);
        const path = value && mediaPath(value);
        if (path) fn(el, attr, value, path);
      }
    }
  }

  function reportMedia() {
    const paths = new Set();
    const broken = new Set();
    eachMedia((el, attr, value, path) => {
      paths.add(path);
      if (el.localName === 'img' && el.complete && el.naturalWidth === 0) broken.add(path);
    });
    post('media', { paths: [...paths], broken: [...broken] });
  }

  function applyMediaVersions() {
    eachMedia((el, attr, value, path) => {
      const v = mediaVersions[path];
      if (!v) return;
      const u = new URL(value, document.baseURI);
      if (u.searchParams.get('bridge-v') === v) return;
      u.searchParams.set('bridge-v', v);
      el.setAttribute(attr, u.href);
      if (el.localName === 'source') el.parentElement?.load?.();
    });
  }

  function refreshMedia(changed) {
    Object.assign(mediaVersions, changed);
    applyMediaVersions();
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
    Idiomorph.morph(document.head, doc.head, { morphStyle: 'innerHTML', callbacks: morphCallbacks });
    Idiomorph.morph(document.body, doc.body, { morphStyle: 'outerHTML', ignoreActiveValue: true, callbacks: morphCallbacks });
    document.title = doc.title;
    state.patches += 1;
    renderMarkdown();
    quotes();
    highlight();
    diagrams();
    enhance();
    applyMediaVersions();
    reportMedia();
    applyAnswers(state.answers);
    const s = shape();
    const payload = await post('shape', s);
    apply(payload);
    propose(proposals(doc));
    return { reload: false };
  }

  // ---- the freeze: pins and boxes on a frozen screen, and the agents bar

  let freeze = { agents() {}, reset() {}, leave() {}, pinsAt() { return false; } };
  if (options.freeze) {
    root.setAttribute('data-bridge-freeze', '');
    const notes = { list: [], pins: new Map(), boxes: new Map(), drafts: {}, pending: null };
    const furniture = (el) => !!el?.closest?.('.bridge-pin, .bridge-composer, .bridge-box, .bridge-agents');

    const place = (el, anchor) => {
      el.style.left = `${anchor.x * 100}vw`;
      el.style.top = `${anchor.y * 100}vh`;
    };

    notes.add = function (id, anchor) {
      if (anchor.w) {
        const box = document.createElement('div');
        box.className = 'bridge-box';
        box.setAttribute('popover', 'manual');
        place(box, anchor);
        box.style.width = `${anchor.w * 100}vw`;
        box.style.height = `${anchor.h * 100}vh`;
        root.appendChild(box);
        box.showPopover();
        notes.boxes.set(id, box);
      }
      const pin = document.createElement('button');
      pin.className = 'bridge-pin';
      pin.setAttribute('popover', 'manual');
      pin.dataset.id = id;
      pin.style.anchorName = `--bridge-pin-${id}`;
      pin.addEventListener('click', () => notes.toggle(id));
      place(pin, anchor);
      root.appendChild(pin);
      pin.showPopover();
      notes.pins.set(id, pin);
      return pin;
    };

    notes.drop = function (id) {
      notes.pins.get(id)?.remove();
      notes.pins.delete(id);
      notes.boxes.get(id)?.remove();
      notes.boxes.delete(id);
      notes.composer(id)?.remove();
    };

    notes.set = function (list) {
      notes.list = list;
      bar.toggleAttribute('data-empty', !list.length);
      const ids = new Set(list.map((n) => n.id));
      for (const id of [...notes.pins.keys()]) if (!ids.has(id) && id !== notes.pending?.id) notes.drop(id);
      list.forEach((note, i) => {
        const pin = notes.pins.get(note.id) || notes.add(note.id, note.anchor);
        pin.dataset.n = i + 1;
        pin.title = note.text;
      });
    };

    notes.composer = (id) => document.querySelector(`.bridge-composer[data-id="${CSS.escape(id)}"]`);

    notes.toggle = function (id) {
      const existing = notes.composer(id);
      if (existing && existing.matches(':popover-open')) { existing.hidePopover(); return; }
      notes.open(id);
    };

    notes.open = function (id) {
      let composer = notes.composer(id);
      if (!composer) {
        composer = document.createElement('div');
        composer.className = 'bridge-composer';
        composer.setAttribute('popover', 'auto');
        composer.dataset.id = id;
        composer.style.positionAnchor = `--bridge-pin-${id}`;
        composer.addEventListener('toggle', (e) => {
          notes.pins.get(id)?.toggleAttribute('data-open', e.newState === 'open');
          if (e.newState === 'open' || !composer.isConnected) return;
          notes.drafts[id] = composer.querySelector('textarea').value;
          if (id === notes.pending?.id && !notes.drafts[id]) notes.cancelPending();
        });
        root.appendChild(composer);
      }
      const note = notes.list.find((x) => x.id === id);
      composer.innerHTML = '<textarea placeholder="What about this?" rows="2"></textarea><div class="bridge-bar">'
        + (note ? '<span><button data-act="delete">Delete</button> <button data-act="cancel">Cancel</button></span>' : '<button data-act="cancel">Cancel</button>')
        + '<button data-act="save" class="bridge-primary">Save <kbd>⌘⏎</kbd></button></div>';
      const box = composer.querySelector('textarea');
      box.value = id in notes.drafts ? notes.drafts[id] : note?.text || '';
      box.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && e.metaKey) { e.preventDefault(); notes.act(id, 'save'); }
        if (e.key === 'Escape') { e.preventDefault(); composer.hidePopover(); }
      });
      composer.querySelectorAll('button').forEach((b) => b.addEventListener('click', () => notes.act(id, b.dataset.act)));
      composer.showPopover();
      notes.fit(composer);
      box.focus();
      box.setSelectionRange(box.value.length, box.value.length);
    };

    notes.fit = function (composer) {
      composer.style.translate = '';
      const r = composer.getBoundingClientRect();
      const dx = Math.max(8 - r.left, 0) + Math.min(innerWidth - 8 - r.right, 0);
      const dy = Math.max(8 - r.top, 0) + Math.min(innerHeight - 8 - r.bottom, 0);
      composer.style.translate = `${dx}px ${dy}px`;
    };

    notes.act = async function (id, action) {
      const composer = notes.composer(id);
      const text = composer.querySelector('textarea').value.trim();
      if (action === 'cancel') { delete notes.drafts[id]; composer.hidePopover(); notes.cancelPending(); return; }
      if (action === 'save' && !text) return;
      const pending = notes.pending?.id === id ? notes.pending : null;
      const list = pending ? (await post('pin', { anchor: pending.anchor, text })).notes
        : await post('note', { id, action: action === 'save' ? 'edit' : 'delete', text });
      delete notes.drafts[id];
      composer.hidePopover();
      composer.remove();
      if (pending) { notes.drop(id); notes.pending = null; }
      notes.set(list);
    };

    notes.cancelPending = function () {
      if (!notes.pending) return;
      notes.drop(notes.pending.id);
      notes.pending = null;
    };

    function startNote(anchor) {
      notes.cancelPending();
      const id = 'new-' + Date.now();
      notes.pending = { id, anchor };
      notes.add(id, anchor).dataset.n = notes.list.length + 1;
      notes.open(id);
    }

    let pressed = null;
    let drawing = null;
    document.addEventListener('click', (e) => {
      if (furniture(e.target)) { pressed = null; return; }
      e.preventDefault();
      e.stopPropagation();
      if (pressed?.composing || pressed?.drew) { pressed = null; return; }
      pressed = null;
      startNote({ x: e.clientX / innerWidth, y: e.clientY / innerHeight });
    }, true);
    document.addEventListener('pointerdown', (e) => {
      if (e.button !== 0 || furniture(e.target)) return;
      pressed = { x: e.clientX, y: e.clientY, composing: !!document.querySelector('.bridge-composer:popover-open'), drew: false };
      if (!pressed.composing) e.preventDefault();
    }, true);
    document.addEventListener('pointermove', (e) => {
      if (!pressed || pressed.composing || !(e.buttons & 1)) return;
      if (!drawing && Math.hypot(e.clientX - pressed.x, e.clientY - pressed.y) < 8) return;
      if (!drawing) { drawing = document.createElement('div'); drawing.className = 'bridge-box bridge-drawing'; root.appendChild(drawing); }
      Object.assign(drawing.style, { left: Math.min(e.clientX, pressed.x) + 'px', top: Math.min(e.clientY, pressed.y) + 'px', width: Math.abs(e.clientX - pressed.x) + 'px', height: Math.abs(e.clientY - pressed.y) + 'px' });
    }, true);
    document.addEventListener('pointerup', () => {
      if (!drawing || !pressed) return;
      const rect = drawing.getBoundingClientRect();
      drawing.remove();
      drawing = null;
      pressed.drew = true;
      startNote({ x: rect.left / innerWidth, y: rect.top / innerHeight, w: rect.width / innerWidth, h: rect.height / innerHeight });
    }, true);

    const still = matchMedia('(prefers-reduced-motion: reduce)');
    const bar = document.createElement('div');
    bar.className = 'bridge-agents';
    bar.setAttribute('popover', 'manual');
    bar.toggleAttribute('data-empty', true);
    root.appendChild(bar);
    bar.showPopover();
    bar.addEventListener('click', (e) => {
      const chip = e.target.closest('button');
      if (chip && !bar.hasAttribute('data-empty')) post('freeze', { send: chip.dataset.session });
    });
    freeze.agents = (list) => {
      const hint = document.createElement('span');
      hint.className = 'bridge-agents-hint';
      hint.textContent = 'Click to pin · drag for a box · Esc to cancel';
      const chips = list.map((agent, i) => {
        const chip = document.createElement('button');
        chip.dataset.session = agent.session;
        chip.toggleAttribute('data-busy', agent.busy);
        chip.toggleAttribute('data-picked', agent.picked);
        const key = document.createElement('kbd');
        key.textContent = i + 1;
        const label = document.createElement('span');
        const name = document.createElement('b');
        name.textContent = agent.name;
        const project = document.createElement('small');
        project.textContent = agent.project;
        label.append(name, ' ', project);
        chip.append(key, label);
        return chip;
      });
      const scroller = document.createElement('div');
      scroller.className = 'bridge-agents-list';
      scroller.append(...chips);
      scroller.addEventListener('wheel', (e) => {
        if (Math.abs(e.deltaY) <= Math.abs(e.deltaX)) return;
        e.preventDefault();
        scroller.scrollLeft += e.deltaY;
      }, { passive: false });
      const draft = document.createElement('button');
      draft.dataset.session = '';
      draft.className = 'bridge-agents-draft';
      draft.textContent = 'Draft';
      bar.replaceChildren(hint, scroller, draft);
      bar.getAnimations().forEach((a) => a.cancel());
      if (still.matches) return;
      const hidden = bar.animate([{ translate: '0 100%' }], { fill: 'forwards' });
      requestAnimationFrame(() => requestAnimationFrame(() => {
        hidden.cancel();
        bar.animate([{ translate: '0 100%' }, { translate: '0 0' }], { duration: 220, easing: 'cubic-bezier(0.23, 1, 0.32, 1)' });
      }));
    };
    freeze.pinsAt = (x, y) => {
      if (y >= bar.offsetTop) return false;
      const el = document.elementFromPoint(x, y);
      return !el || getComputedStyle(el).cursor.startsWith('url(');
    };
    freeze.leave = () => {
      if (!still.matches) bar.animate([{ translate: '0 0' }, { translate: '0 100%' }], { duration: 160, easing: 'cubic-bezier(0.4, 0, 1, 1)', fill: 'forwards' });
    };
    freeze.reset = () => {
      notes.cancelPending();
      notes.drafts = {};
      notes.set([]);
    };
    document.addEventListener('keydown', (e) => {
      if (e.target.closest?.('textarea, input') || document.querySelector('.bridge-composer:popover-open')) return;
      if (e.key === 'Escape') { e.preventDefault(); post('freeze', { key: 'escape' }); }
      if (e.key === 'Enter' && !e.target.closest?.('button')) { e.preventDefault(); bar.querySelector('button[data-picked]')?.click(); }
      if (/^[1-9]$/.test(e.key)) { e.preventDefault(); bar.querySelectorAll('button:not(.bridge-agents-draft)')[e.key - 1]?.click(); }
    });
    let frame = 0;
    document.addEventListener('pointermove', (e) => {
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        if (pressed || document.querySelector('.bridge-composer:popover-open') || e.target.closest?.('.bridge-agents')) post('hover');
        else post('hover', { x: e.clientX / innerWidth, y: e.clientY / innerHeight });
      });
    });
    root.addEventListener('pointerleave', () => post('hover'));
    root.style.setProperty('--bridge-cursor', pinCursor());
  }

  function pinCursor() {
    const probe = document.createElement('i');
    probe.style.color = 'AccentColor';
    root.appendChild(probe);
    const accent = getComputedStyle(probe).color;
    probe.remove();
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="28" height="32" viewBox="0 0 28 32"><path d="M14 29.6 L6.2 21.8 A11 11 0 1 1 21.8 21.8 Z" fill="${accent}" stroke="white" stroke-width="2" stroke-linejoin="round"/><path d="M14 9.5v8M10 13.5h8" stroke="white" stroke-width="2" stroke-linecap="round"/></svg>`;
    return `url("data:image/svg+xml,${encodeURIComponent(svg)}") 14 29, crosshair`;
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
      record(key, value, true, true);
    } catch (e) { /* malformed */ }
  });
  document.addEventListener('bridge:clear', () => clear(root.dataset.bridgeClear));
  document.addEventListener('bridge:send', send);
  document.addEventListener('bridge:attach', () => post('attach'));
  document.addEventListener('bridge:error', () => post('error', { text: root.dataset.bridgeError }));
  document.addEventListener('bridge:rendered', async () => {
    if (!started) { ready(); return; }
    const payload = await post('shape', shape());
    apply(payload);
  });

  globalThis.__bridge = {
    patch,
    status: setStatus,
    agents: (list) => freeze.agents(list),
    reset: () => freeze.reset(),
    pinsAt: (x, y) => freeze.pinsAt(x, y),
    leave: () => freeze.leave(),
    state,
    shape,
    setData,
    drive,
    applyDrives,
    frameRefused,
    refreshMedia,
  };

  // Reports class tokens no stylesheet defines, which an agent otherwise guesses
  // at without noticing, and classes both the kit and the page define, which
  // look styled but mix two meanings. The CLI prints both on stderr.
  function auditClasses() {
    if (options.built || !options.local) return { unknown: [], both: [] };
    const kit = new Set(), page = new Set();
    const note = (text, into) => { for (const m of text.matchAll(/\.(-?[_a-zA-Z][\w-]*)/g)) into.add(m[1]); };
    note(__BRIDGE_CSS.page, kit);
    const walk = (rules) => { for (const r of rules) { if (r.selectorText) note(r.selectorText, page); if (r.cssRules) walk(r.cssRules); } };
    for (const element of document.querySelectorAll('style, link[rel~="stylesheet"]')) {
      if (ours(element)) continue;
      try { walk(element.sheet.cssRules); } catch { return { unknown: [], both: [] }; }
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

  function proposals(doc) {
    const out = {};
    for (const el of doc.querySelectorAll('input[data-record], select[data-record], textarea[data-record]')) {
      const key = el.dataset.record;
      if (key in out || ours(el)) continue;
      if (el.type === 'radio') { if (el.checked) out[key] = el.value; }
      else if (el.type === 'checkbox') out[key] = el.checked;
      else if (el.type === 'range' || el.type === 'number') { if (el.value !== '') out[key] = valueOf(el); }
      else if (el.value) out[key] = valueOf(el);
    }
    for (const group of doc.querySelectorAll('[data-record]:not(input):not(select):not(textarea):not([data-value]):not(.color):not(.swatches)')) {
      const key = group.dataset.record;
      if (key in out || ours(group)) continue;
      const boxes = [...group.querySelectorAll('input[type=checkbox]')];
      const radio = group.querySelector('input[type=radio]:checked');
      if (radio) out[key] = radio.value;
      else if (boxes.length) out[key] = boxes.length === 1 ? boxes[0].checked : boxes.filter((i) => i.checked).map((i) => i.value);
    }
    return out;
  }

  function propose(values) {
    if (state.readOnly) return;
    state.proposed = values;
    markDefaults();
    post('propose', { values });
  }

  let started = false;
  async function ready() {
    if (started) return;
    started = true;
    currentScripts = scriptSignature(document);
    renderMarkdown();
    await quotes();
    highlight();
    await diagrams();
    enhance();
    const picture = document.querySelector('.doc-image img');
    if (picture) {
      const report = () => post('size', { width: picture.naturalWidth, height: picture.naturalHeight });
      if (picture.complete && picture.naturalWidth) report(); else picture.addEventListener('load', report, { once: true });
    }
    const proposed = proposals(document);
    const payload = await post('ready', { title: document.title, classes: auditClasses(), ...shape() });
    apply(payload);
    propose(proposed);
    reportMedia();
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
