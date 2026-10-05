// `import { record, useRecord } from '@bridge'` inside a page. Needed only for
// controls whose value never reaches a DOM input (Slider, Select, Rating,
// ColorInput...); anything that renders a real input records through
// data-record on its own.
import { useState, useCallback } from 'react';

export function record(key, value) {
  document.documentElement.dataset.bridgeRecord = JSON.stringify({ key, value });
  document.dispatchEvent(new Event('bridge:record'));
}

export function useRecord(key, initial) {
  const answers = window.__bridgeAnswers || {};
  const [value, setValue] = useState(key in answers ? answers[key] : initial);
  const set = useCallback((v) => { setValue(v); record(key, v); }, [key]);
  return [value, set];
}

export function send() {
  document.dispatchEvent(new Event('bridge:send'));
}

// Set a CSS custom property on the page and in every embedded frame, so a
// control can drive a live site inside an iframe. Within your own React tree
// an inline style is enough; this is for what you do not own.
export function drive(prop, value, target, frameTarget) {
  document.documentElement.dataset.bridgeDrive = JSON.stringify({ prop, value, target: target || null, frameTarget: frameTarget || null });
  document.dispatchEvent(new Event('bridge:drive'));
}
