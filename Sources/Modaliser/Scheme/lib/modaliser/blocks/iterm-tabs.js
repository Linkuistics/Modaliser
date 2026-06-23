/* iterm-tabs.js — block renderer for the labelled iTerm tabs list. */

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
  window.overlayBlockRenderers['iterm-tabs'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const tabs = block.tabs || [];
    // block.selected — the selection-cursor row index (list-cursor-k6) when
    // this list owns the cursor. .is-focused (the moving cursor) is distinct
    // from .current (the actually-focused tab); a row can carry both.
    const selected = typeof block.selected === 'number' ? block.selected : -1;
    for (let i = 0; i < tabs.length; i++) {
      const t = tabs[i];
      let cls = t.current ? 'it-row current' : 'it-row';
      if (i === selected) cls += ' is-focused';
      const row = el('div', { class: cls },
        el('span', { class: 'entry-key', text: t.label }),
        el('span', { class: 'entry-arrow', text: '→' }),
        el('span', { class: 'entry-label', text: t.title || 'Tab' })
      );
      container.appendChild(row);
    }
  };
})();
