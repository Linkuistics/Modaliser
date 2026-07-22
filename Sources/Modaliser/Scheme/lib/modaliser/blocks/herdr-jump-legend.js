/* herdr-jump-legend.js — block renderer for the herdr Jump legend panel
   (jump-space-legend-overlay-k40). One row per assigned jump target: the
   label, an arrow, a kind badge, and the target name. Display-only —
   no .current marker, no selection cursor: the jump label here is never
   dispatchable, dispatch already lives in the FSM provider edges.
   The kind rides a fixed-width badge (mirroring herdr-list.js's agent
   status badge) ahead of the title rather than a trailing dimmed
   column — a trailing column competing with the title for the panel's
   remaining width squeezed down to a single truncated character on a
   narrow panel; a badge has no such competition. */

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
  window.overlayBlockRenderers['herdr-jump-legend'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const rows = block.rows || [];
    for (const r of rows) {
      container.appendChild(el('div', { class: 'jl-row' },
        el('span', { class: 'entry-key', text: r.label }),
        el('span', { class: 'entry-arrow', text: '→' }),
        r.detail ? el('span', { class: 'jl-badge' }, r.detail) : null,
        el('span', { class: 'entry-label', text: r.title || r.label })
      ));
    }
  };
})();
