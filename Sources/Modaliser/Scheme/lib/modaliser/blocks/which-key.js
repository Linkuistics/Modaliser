/* which-key.js — renderer for the which-key block.
 *
 * Payload shape:
 *   { type: "which-key",
 *     columns: [                              // one entry per overlay column
 *       [ <segment>, <segment>, ... ],        // column 1, top-to-bottom
 *       [ <segment>, ... ],                   // column 2
 *       ...
 *     ] }
 *
 * Each segment is either:
 *   {kind: "misc",     rows: [<row>, ...]}                 // coalesced loose entries
 *   {kind: "category", label: "Move", rows: [<row>, ...]}  // explicit category
 *
 * Each row: {key, label, isGroup, isSticky}.
 *
 * Columns are precomputed Scheme-side (distribute-which-key-columns in
 * overlay.scm) so short categories backfill the space under other short
 * ones. This renderer draws one .wk-col element per column; which-key.css
 * lays them out as an equal-width grid. --overlay-cols is set inline here
 * from the column count.
 */

(function() {
  function el(tag, attrs, ...kids) {
    const e = document.createElement(tag);
    if (attrs) {
      for (const k in attrs) {
        if (k === 'class') e.className = attrs[k];
        else if (k === 'text') e.textContent = attrs[k];
        else if (k === 'html') e.innerHTML = attrs[k];
        else e.setAttribute(k, attrs[k]);
      }
    }
    for (const kid of kids) {
      if (kid == null) continue;
      e.appendChild(typeof kid === 'string' ? document.createTextNode(kid) : kid);
    }
    return e;
  }

  function renderRow(row) {
    const displayKey = row.key === ' ' ? '␣' : row.key;
    const labelClass = row.isGroup ? 'entry-label group-label' : 'entry-label';
    let labelText = row.isGroup ? (row.label + ' …') : row.label;
    const labelNode = el('span', { class: labelClass });
    if (row.isSticky) {
      const marker = el('span', { class: 'entry-sticky-marker', text: '↻' });
      labelNode.appendChild(marker);
      labelNode.appendChild(document.createTextNode(labelText));
    } else {
      labelNode.textContent = labelText;
    }
    return el('div', { class: 'wk-row' },
      // key is ready HTML from key-display-html (modifier glyphs wrapped
      // in <span class="sigil-mod">) — set as innerHTML, not textContent.
      el('span', { class: 'entry-key', html: displayKey }),
      el('span', { class: 'entry-arrow', text: '→' }),
      labelNode
    );
  }

  function renderMisc(seg) {
    const col = el('div', { class: 'wk-misc' });
    for (const row of (seg.rows || [])) {
      col.appendChild(renderRow(row));
    }
    return col;
  }

  function renderCategory(seg) {
    const cat = el('div', { class: 'wk-category' });
    cat.appendChild(el('h4', { class: 'wk-category-label', text: seg.label }));
    for (const row of (seg.rows || [])) {
      cat.appendChild(renderRow(row));
    }
    return cat;
  }

  // Expose the per-row renderer so the panel-grid renderer (overlay.js)
  // draws panel key-rows with IDENTICAL markup — one row renderer, no
  // divergence. (When the which-key block is retired with the auto-layout
  // in config-migration-k8, overlay.js keeps an identical local fallback,
  // so panel rows render the same either way.)
  window.overlayRenderRow = renderRow;

  window.overlayBlockRenderers = window.overlayBlockRenderers || {};
  window.overlayBlockRenderers['which-key'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const cols = el('div', { class: 'wk-columns' });
    const columns = block.columns || [];
    // One grid track per column; CSS reads --overlay-cols.
    cols.style.setProperty('--overlay-cols', String(Math.max(1, columns.length)));
    for (const column of columns) {
      const colEl = el('div', { class: 'wk-col' });
      for (const seg of column) {
        if (seg.kind === 'category') colEl.appendChild(renderCategory(seg));
        else if (seg.kind === 'misc') colEl.appendChild(renderMisc(seg));
      }
      cols.appendChild(colEl);
    }
    container.appendChild(cols);
  };
})();
