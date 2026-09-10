/* part-list.js — block renderer for a window part listing
   (vscode-part-panels-k7). One row per part of the frontmost window, in
   listing order: the jump label, an arrow, the part's name, and a dimmed
   trailing detail. The active row carries .current, the same treatment the
   sibling list blocks use.

   ONE renderer, two panels. The Terminal listing's row is a name plus a
   cwd and the Editor listing's is a filename plus a workspace-relative
   path — the same presentation with different content, so it is written
   once. The two panels are told apart on the Scheme side by an explicit
   block 'id; the DOM class and this lookup are keyed on the block TYPE,
   which both share, so both render through here.

   Display-only — no selection cursor: the label is dispatched by the FSM
   provider edges (modaliser jump-list) mints for the composing library,
   never by this block.

   TWO kinds of row render without an arrow, and both are expected rather
   than bugs. A blank label is a tail past the user's label pools, which
   still renders because the listing is a picture of what is open. An
   `inert` row is a tab of a kind with no specified activation — it has a
   label and nothing behind it, and drawing an arrow out of a keycap that
   does nothing would be the one thing worse than drawing no arrow. The
   keycap span is emitted either way so the names stay aligned down the
   panel. */

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
  window.overlayBlockRenderers['part-list'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const rows = block.rows || [];
    for (const r of rows) {
      const dispatches = !!r.label && !r.inert;
      const cls = ['pt-row'];
      if (r.current) cls.push('current');
      if (r.inert) cls.push('inert');
      container.appendChild(el('div', { class: cls.join(' ') },
        el('span', { class: 'entry-key', text: r.label || '' }),
        el('span', { class: 'entry-arrow', text: dispatches ? '→' : '' }),
        /* The dirty marker is a leading dot on the name rather than a
           column of its own: it is one character, it is absent on most
           rows, and a column reserved for it would indent every clean
           name for the sake of the occasional dirty one. */
        el('span', { class: 'entry-label', text: (r.dirty ? '● ' : '') + (r.name || '') }),
        r.detail ? el('span', { class: 'pt-detail', text: r.detail }) : null
      ));
    }
  };
})();
