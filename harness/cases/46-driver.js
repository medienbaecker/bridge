const keys = new Set([...document.querySelectorAll("[data-record]")].map((e) => e.dataset.record));
const fire = (el, t) => el.dispatchEvent(new Event(t, { bubbles: true }));
const undriven = [];
for (const key of keys) {
  const els = [...document.querySelectorAll(`[data-record="${key}"]`)];
  const el = els[0];
  // The colour host carries a data-value of its own once built, so it goes before the div shape.
  if (el.classList.contains("color")) { const r = el.querySelector("input[type=range]"); if (r) { r.value = r.min; fire(r, "input"); fire(r, "change"); continue; } }
  if (els.some((e) => e.dataset.value !== undefined)) { (els.find((e) => !e.hasAttribute("data-selected")) || el).click(); continue; }
  if (el.classList.contains("swatches")) { const b = el.querySelector("[data-color]"); if (b) { b.click(); continue; } }
  if (el.matches("input[type=radio]")) { (els.find((e) => !e.checked) || el).click(); continue; }
  if (el.matches("input[type=checkbox]")) { el.click(); continue; }
  if (el.matches("input[type=range], input[type=number]")) { el.value = el.max || "9"; fire(el, "input"); fire(el, "change"); continue; }
  if (el.matches("input, textarea")) { el.value = "driven"; fire(el, "input"); fire(el, "change"); continue; }
  if (el.matches("select")) { el.selectedIndex = el.options.length - 1; fire(el, "change"); continue; }
  const inner = el.querySelector("input[type=radio]:not(:checked), input[type=checkbox], input[type=range], input, textarea, select, [contenteditable]");
  if (inner && inner.matches("input[type=radio], input[type=checkbox]")) { inner.click(); continue; }
  if (inner && inner.matches("input[type=range], input[type=number]")) { inner.value = inner.max || "9"; fire(inner, "input"); fire(inner, "change"); continue; }
  if (inner && inner.matches("input, textarea")) { inner.value = "driven"; fire(inner, "input"); fire(inner, "change"); continue; }
  if (inner && inner.isContentEditable) { inner.textContent = "driven"; fire(inner, "input"); continue; }
  if (el.isContentEditable) { el.textContent = "driven"; fire(el, "input"); continue; }
  undriven.push(key);
}
return { keys: [...keys].sort(), undriven };
