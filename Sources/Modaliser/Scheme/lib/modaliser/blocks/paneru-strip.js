/* paneru-strip.js — block renderer for the paneru Strip listing
   (paneru-strip-list-k7). One row per window on the active virtual
   workspace, in strip order: the jump label, an arrow, the app name, and
   the window title as dimmed trailing detail. The paneru-focused row
   carries .current, the same treatment the sibling list blocks use.

   Display-only — no selection cursor: the label is dispatched by the FSM
   provider edges (modaliser wms paneru)'s strip-provider mints, never by
   this block.

   A blank label is expected, not a bug: a strip longer than the user's
   label pools leaves a tail unlabelled, and those rows still render
   because the listing is a picture of the strip. The keycap span is
   emitted either way so the columns stay aligned down the panel. */

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
  window.overlayBlockRenderers['paneru-strip'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const rows = block.rows || [];
    for (const r of rows) {
      /* The arrow is suppressed on an unlabelled row — an arrow pointing
         out of an empty keycap reads as a broken binding rather than as a
         row that simply outran the alphabet. */
      const labelled = !!r.label;
      container.appendChild(el('div', { class: r.focused ? 'ps-row current' : 'ps-row' },
        el('span', { class: 'entry-key', text: r.label || '' }),
        el('span', { class: 'entry-arrow', text: labelled ? '→' : '' }),
        el('span', { class: 'entry-label', text: r.app || 'Window' }),
        r.title ? el('span', { class: 'ps-detail', text: r.title }) : null
      ));
    }
  };
})();
