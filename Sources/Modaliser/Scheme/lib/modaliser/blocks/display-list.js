/* display-list.js — block renderer for the labelled displays list. Each row:
 * a move keycap (plain letter), the display name, and a right-aligned Shift+
 * letter focus hint. */

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
  window.overlayBlockRenderers['display-list'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const displays = block.displays || [];
    for (let i = 0; i < displays.length; i++) {
      const d = displays[i];
      const name = d.primary ? (d.name + ' · primary') : d.name;
      const focus = '⇧' + (d.label || '').toUpperCase();   // ⇧H
      const row = el('div', { class: 'dl-row' },
        el('span', { class: 'entry-key', text: d.label }),
        el('span', { class: 'entry-arrow', text: '→' }),    // →
        el('span', { class: 'entry-label', text: name }),
        el('span', { class: 'dl-detail', text: focus })
      );
      container.appendChild(row);
    }
  };
})();
