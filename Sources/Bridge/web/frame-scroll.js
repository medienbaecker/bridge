(() => {
  if (window === window.top) return;
  const place = (start, size, view, mode) => {
    if (mode === 'start') return start;
    if (mode === 'end') return start + size - view;
    if (mode === 'center') return start + size / 2 - view / 2;
    if (start < 0) return start;
    return start + size > view ? Math.min(start, start + size - view) : 0;
  };
  const into = (el, block, inline, behavior) => {
    const top = document.scrollingElement;
    for (let box = el.parentElement; box && box !== top && box !== document.body; box = box.parentElement) {
      const s = getComputedStyle(box);
      if (!/(auto|scroll)/.test(s.overflowX + s.overflowY)) continue;
      const r = el.getBoundingClientRect(), b = box.getBoundingClientRect();
      box.scrollBy({ top: place(r.top - b.top - box.clientTop, r.height, box.clientHeight, block),
        left: place(r.left - b.left - box.clientLeft, r.width, box.clientWidth, inline), behavior });
    }
    const r = el.getBoundingClientRect();
    window.scrollBy({ top: place(r.top, r.height, innerHeight, block), left: place(r.left, r.width, innerWidth, inline), behavior });
  };
  Element.prototype.scrollIntoView = function (arg) {
    const o = arg && typeof arg === 'object' ? arg : {};
    into(this, o.block || (arg === false ? 'end' : 'start'), o.inline || 'nearest', o.behavior);
  };
  Element.prototype.scrollIntoViewIfNeeded = function (center) {
    into(this, center === false ? 'nearest' : 'center', center === false ? 'nearest' : 'center');
  };
})();
