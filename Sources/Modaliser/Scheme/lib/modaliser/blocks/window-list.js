/* window-list.js — block renderer for the labelled windows list. */

(function() {
  function el(tag, attrs, ...kids) {
    const e = document.createElement(tag);
    if (attrs) {
      for (const k in attrs) {
        if (k === 'class') e.className = attrs[k];
        else if (k === 'text') e.textContent = attrs[k];
        else e.setAttribute(k, attrs[k]);
      }
    }
    for (const kid of kids) {
      if (kid == null) continue;
      e.appendChild(typeof kid === 'string' ? document.createTextNode(kid) : kid);
    }
    return e;
  }

  window.overlayBlockRenderers = window.overlayBlockRenderers || {};
  window.overlayBlockRenderers['window-list'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const windows = block.windows || [];
    // block.selected is the selection-cursor row index (list-cursor-k6) when
    // this list owns the cursor; absent otherwise. The focused row gets
    // .is-focused (accent left-bar + tint, base.css).
    const selected = typeof block.selected === 'number' ? block.selected : -1;
    for (let i = 0; i < windows.length; i++) {
      const w = windows[i];
      const name = w.title ? (w.app + ' · ' + w.title) : w.app;
      let cls = w.visible ? 'wl-row' : 'wl-row dulled';
      if (i === selected) cls += ' is-focused';
      const row = el('div', { class: cls },
        el('span', { class: 'entry-key', text: w.label }),
        el('span', { class: 'entry-arrow', text: '→' }),
        el('span', { class: 'entry-label', text: name })
      );
      container.appendChild(row);
    }
  };
})();
