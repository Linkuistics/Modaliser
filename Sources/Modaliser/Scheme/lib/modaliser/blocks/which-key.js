/* which-key.js — renderer for the which-key block.
 *
 * Payload shape:
 *   { type: "which-key",
 *     segments: [
 *       {kind: "misc",     row: {key, label, isGroup, isSticky}},
 *       {kind: "category", label: "Move", rows: [<row>, ...]},
 *       ...
 *     ] }
 *
 * Lays segments out in a CSS multi-column flow (column-fill: auto)
 * scoped under .block-which-key. Categories are atomic units
 * (.wk-category, break-inside: avoid). Misc rows are bare siblings
 * with no break rule — each flows independently across columns.
 */

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
      el('span', { class: 'entry-key', text: displayKey }),
      el('span', { class: 'entry-arrow', text: '→' }),
      labelNode
    );
  }

  function renderCategory(seg) {
    const cat = el('div', { class: 'wk-category' });
    cat.appendChild(el('h4', { class: 'wk-category-label', text: seg.label }));
    for (const row of (seg.rows || [])) {
      cat.appendChild(renderRow(row));
    }
    return cat;
  }

  window.overlayBlockRenderers = window.overlayBlockRenderers || {};
  window.overlayBlockRenderers['which-key'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const cols = el('div', { class: 'wk-columns' });
    // Column count is precomputed Scheme-side to match the legacy list
    // renderer's aspect-ratio-based layout; default to 1 if absent.
    if (typeof block.cols === 'number' && block.cols > 0) {
      cols.style.setProperty('--overlay-cols', String(block.cols));
    }
    for (const seg of (block.segments || [])) {
      if (seg.kind === 'category') {
        cols.appendChild(renderCategory(seg));
      } else if (seg.kind === 'misc') {
        cols.appendChild(renderRow(seg.row));
      }
    }
    container.appendChild(cols);
  };
})();
