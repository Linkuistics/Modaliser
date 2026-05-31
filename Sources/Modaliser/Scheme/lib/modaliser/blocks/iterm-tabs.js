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
    for (const t of tabs) {
      const cls = t.current ? 'it-row current' : 'it-row';
      const row = el('div', { class: cls },
        el('span', { class: 'entry-key', text: t.label }),
        el('span', { class: 'entry-arrow', text: '→' }),
        el('span', { class: 'entry-label', text: t.title || 'Tab' })
      );
      container.appendChild(row);
    }
  };
})();
