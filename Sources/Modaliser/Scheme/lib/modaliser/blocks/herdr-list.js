/* herdr-list.js — block renderer for herdr's labelled live lists (panes /
   tabs / workspaces / agents). One row per entry: a digit keycap, the entry
   title, and — for panes/agents — a dimmed detail (cwd / workspace·tab). An
   agents row additionally carries a color-coded status badge between the
   arrow and the title (its presence is what `r.status` signals; the row gets
   .hl-agent so the grid opens a badge column). The focused entry gets
   .current; the selection cursor (when this list owns it) gets .is-focused. */

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
  window.overlayBlockRenderers['herdr-list'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const rows = block.rows || [];
    // block.selected — the selection-cursor row index (list-cursor-k6) when
    // this list owns the cursor. .is-focused (the moving cursor) is distinct
    // from .current (the herdr-focused entry); a row can carry both.
    const selected = typeof block.selected === 'number' ? block.selected : -1;
    for (let i = 0; i < rows.length; i++) {
      const r = rows[i];
      let cls = r.focused ? 'hl-row current' : 'hl-row';
      // Only agent rows carry r.status → a badge column; the modifier class
      // widens the grid so the badge sits between the arrow and the title,
      // leaving the panes/tabs/workspaces four-column layout untouched.
      if (r.status) cls += ' hl-agent';
      if (i === selected) cls += ' is-focused';
      const row = el('div', { class: cls },
        el('span', { class: 'entry-key', text: r.label }),
        el('span', { class: 'entry-arrow', text: '→' }),
        r.status ? el('span', { class: 'hl-badge hl-badge-' + r.status, text: r.status }) : null,
        el('span', { class: 'entry-label', text: r.title || 'Item' }),
        r.detail ? el('span', { class: 'hl-detail', text: r.detail }) : null
      );
      container.appendChild(row);
    }
  };
})();
