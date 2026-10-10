// The page-side API, injected into the page's own world before its scripts:
// bridge.set(key, value), bridge.clear(key), bridge.get(key[, { own }]),
// bridge.isDefault(key), bridge.ready(fn). Values cross to the runtime through DOM
// events; keys a page touches are declared as its questions so rewrites are
// versioned the same way as data-record controls. A value the page proposed (a
// checked radio) and the user never touched is kept apart from their answers:
// get(key) returns it, get(key, { own: true }) answers undefined for it, and
// isDefault(key) says which it is. A page restoring its state must not put such
// a value back as a choice.
(() => {
  if (window.bridge) return;
  const answers = window.__bridgeAnswers || (window.__bridgeAnswers = {});
  const proposed = window.__bridgeProposed || {};
  const root = document.documentElement;
  // The page's questions so far come along as a seed and are declared the moment
  // the page first uses the API, so a reopen hashes the same page before the
  // script has touched every key again. A page that never calls in never declares.
  const seeded = Array.isArray(window.__bridgeApi) ? window.__bridgeApi : [];
  const declared = new Set();
  let seededIn = false;
  const declare = (key) => {
    let changed = false;
    if (!seededIn) { seededIn = true; for (const k of seeded) if (!declared.has(k)) { declared.add(k); changed = true; } }
    if (key !== undefined && !declared.has(key)) { declared.add(key); changed = true; }
    if (!changed) return;
    root.dataset.bridgeDeclare = JSON.stringify([...declared]);
    document.dispatchEvent(new Event('bridge:declare'));
  };
  const report = (message, file, line) => {
    const where = file ? ` (${file.split('/').pop()}${line ? ':' + line : ''})` : '';
    root.dataset.bridgeError = String(message) + where;
    document.dispatchEvent(new Event('bridge:error'));
  };
  window.addEventListener('error', (e) => {
    if (e.message === 'Script error.' && !e.lineno) report('a script from another origin threw, and WebKit hides its message: load it from a file beside the page to see the error and its line');
    else if (e.message) report(e.message, e.filename, e.lineno);
  });
  window.addEventListener('unhandledrejection', (e) => report('Unhandled rejection: ' + (e.reason && e.reason.message || e.reason)));
  const callbacks = [];
  let fired = false;
  const fire = () => {
    if (fired) return;
    fired = true;
    for (const fn of callbacks) { try { fn(); } catch (e) { console.error(e); report('in bridge.ready: ' + (e && e.message || e), e && e.sourceURL, e && e.line); } }
    root.dataset.bridgePageReady = '1';
    document.dispatchEvent(new Event('bridge:page-ready'));
  };
  window.bridge = {
    set(key, value) {
      declare(key);
      answers[key] = value;
      root.dataset.bridgeRecord = JSON.stringify({ key, value });
      document.dispatchEvent(new Event('bridge:record'));
    },
    clear(key) {
      declare(key);
      delete answers[key];
      root.dataset.bridgeClear = key;
      document.dispatchEvent(new Event('bridge:clear'));
    },
    get(key, options) { declare(key); return key in answers || (options && options.own) ? answers[key] : proposed[key]; },
    isDefault(key) { declare(key); return !(key in answers) && key in proposed; },
    ready(fn) {
      declare();
      root.dataset.bridgeApi = '1';
      if (fired) fn(); else callbacks.push(fn);
    },
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fire); else fire();
})();
