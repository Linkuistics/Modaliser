/* iterm-panes.js — block renderer for the labelled iTerm panes list. */

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
  window.overlayBlockRenderers['iterm-panes'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const panes = block.panes || [];
    for (const p of panes) {
      const text = p.title || p.fallback || 'Pane';
      const row = el('div', { class: 'ip-row' },
        el('span', { class: 'entry-key', text: p.label }),
        el('span', { class: 'entry-arrow', text: '→' }),
        el('span', { class: 'entry-label', text: text })
      );
      container.appendChild(row);
    }
  };
})();
