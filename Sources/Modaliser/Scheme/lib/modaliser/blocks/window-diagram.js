/* window-diagram.js — block renderer for the panel-grid block.
 *
 * Lives next to window-diagram.sld; loaded via add-overlay-asset-file!
 * at library import time. Registers itself on
 * window.overlayBlockRenderers['window-diagram'].
 *
 * Payload shape (one block in the blocks-list payload):
 *   { type: "window-diagram",
 *     panels: [
 *       { type: "grid",   cols, rows, cells: [{key, col, row, colSpan, rowSpan}, ...] },
 *       { type: "center", key },
 *       { type: "fill",   key },
 *     ] }
 *
 * Lifted with no behavioural change from lib/modaliser/diagram-panel.js
 * — same DOM structure, same CSS class names (.diagram-panel, .diagram-
 * cell, etc.) so the existing stylesheet keeps working. The block lives
 * inside a per-block container (.block.block-window-diagram); the actual
 * panel grid is the .diagram-panel-grid child the JS appends.
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

  function svg(tag, attrs, ...kids) {
    const e = document.createElementNS('http://www.w3.org/2000/svg', tag);
    if (attrs) for (const k in attrs) e.setAttribute(k, attrs[k]);
    for (const kid of kids) if (kid) e.appendChild(kid);
    return e;
  }

  function gridLineClasses(cell) {
    const cls = ['diagram-cell'];
    if (cell.key) cls.push('has-key');
    if (cell.col > 1) cls.push('left-line');
    if (cell.row > 1) cls.push('top-line');
    return cls.join(' ');
  }

  function renderGridPanel(panel) {
    const div = el('div', {
      class: 'diagram-panel grid',
      style: `grid-template-columns: repeat(${panel.cols}, 1fr); grid-template-rows: repeat(${panel.rows}, 1fr);`
    });
    const covered = new Set();
    for (const cell of panel.cells) {
      for (let dr = 0; dr < (cell.rowSpan || 1); dr++) {
        for (let dc = 0; dc < (cell.colSpan || 1); dc++) {
          covered.add((cell.col + dc) + ',' + (cell.row + dr));
        }
      }
    }
    for (const cell of panel.cells) {
      div.appendChild(el('div', {
        class: gridLineClasses(cell),
        style: `grid-column: ${cell.col} / span ${cell.colSpan}; grid-row: ${cell.row} / span ${cell.rowSpan};`,
        text: cell.key || ''
      }));
    }
    for (let r = 1; r <= panel.rows; r++) {
      for (let c = 1; c <= panel.cols; c++) {
        if (covered.has(c + ',' + r)) continue;
        const placeholder = { col: c, row: r, colSpan: 1, rowSpan: 1, key: null };
        div.appendChild(el('div', {
          class: gridLineClasses(placeholder),
          style: `grid-column: ${c} / span 1; grid-row: ${r} / span 1;`
        }));
      }
    }
    return div;
  }

  function renderFillPanel(panel) {
    return el('div', { class: 'diagram-panel fill', text: panel.key });
  }

  function renderCenterPanel(panel) {
    const s = svg('svg', { viewBox: '0 0 102 60', preserveAspectRatio: 'none' });
    s.appendChild(svg('rect', { class: 'diagram-inner-fill', x: '35', y: '20', width: '32', height: '20' }));
    s.appendChild(svg('rect', { class: 'diagram-stroke', x: '35', y: '20', width: '32', height: '20' }));
    const shafts = [
      ['51','6','51','12'],
      ['51','54','51','48'],
      ['7','30','27','30'],
      ['95','30','75','30'],
    ];
    for (const [x1, y1, x2, y2] of shafts) {
      s.appendChild(svg('line', { class: 'diagram-stroke', x1, y1, x2, y2 }));
    }
    const heads = [
      '51,17 47,11 55,11',
      '51,43 47,49 55,49',
      '32,30 26,26 26,34',
      '70,30 76,26 76,34',
    ];
    for (const points of heads) {
      s.appendChild(svg('polygon', { class: 'diagram-arrow', points }));
    }
    const t = svg('text', { class: 'diagram-key', x: '51', y: '35', 'text-anchor': 'middle' });
    t.textContent = panel.key;
    s.appendChild(t);
    return el('div', { class: 'diagram-panel center' }, s);
  }

  function renderPanel(panel) {
    switch (panel.type) {
      case 'grid':   return renderGridPanel(panel);
      case 'fill':   return renderFillPanel(panel);
      case 'center': return renderCenterPanel(panel);
      default:
        console.warn('window-diagram: unknown panel type', panel.type);
        return el('div');
    }
  }

  window.overlayBlockRenderers = window.overlayBlockRenderers || {};
  window.overlayBlockRenderers['window-diagram'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const grid = el('div', { class: 'diagram-panel-grid' });
    for (const panel of (block.panels || [])) {
      grid.appendChild(renderPanel(panel));
    }
    container.appendChild(grid);
  };
})();
