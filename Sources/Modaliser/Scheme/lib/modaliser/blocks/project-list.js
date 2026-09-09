/* project-list.js — block renderer for the Project listing
   (vscode-project-panel-k4). One row per open project, in listing order:
   the jump label, an arrow, and the project's name.

   Display-only — no selection cursor: the label is dispatched by the FSM
   provider edges (modaliser jump-list) mints for the composing library,
   never by this block.

   A blank label is expected, not a bug: more projects than the user's
   label pools cover leaves a tail unlabelled, and those rows still render
   because the listing is a picture of what is open. The keycap span is
   emitted either way so the names stay aligned down the panel. */

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
  window.overlayBlockRenderers['project-list'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const rows = block.rows || [];
    for (const r of rows) {
      /* The arrow is suppressed on an unlabelled row — an arrow pointing
         out of an empty keycap reads as a broken binding rather than as a
         row that simply outran the alphabet. */
      const labelled = !!r.label;
      container.appendChild(el('div', { class: 'pl-row' },
        el('span', { class: 'entry-key', text: r.label || '' }),
        el('span', { class: 'entry-arrow', text: labelled ? '→' : '' }),
        el('span', { class: 'entry-label', text: r.name || 'Project' })
      ));
    }
  };
})();
