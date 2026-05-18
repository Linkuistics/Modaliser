/* diagram-panel.js — renderer for groups carrying 'renderer 'diagram.
 *
 * Lives next to diagram-panel.sld; loaded into the overlay via
 * (add-overlay-asset! 'js …) at library-import time.
 *
 * Payload shape:
 *   { type: "diagram",
 *     panels: [
 *       { type: "grid",   cols, rows, cells: [{key, col, row, colSpan, rowSpan}, ...] },
 *       { type: "center", key },
 *       { type: "fill",   key },
 *     ],
 *     entries: [{key, label, isGroup}, ...]
 *   }
 *
 * The 3rd "column" of the panel-grid layout is reserved for the text
 * entries strip — they sit beneath the top-right panel.
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

  // For a grid panel: figure out which cells need a left-line / top-line.
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
    for (const cell of panel.cells) {
      const c = el('div', {
        class: gridLineClasses(cell),
        style: `grid-column: ${cell.col} / span ${cell.colSpan}; grid-row: ${cell.row} / span ${cell.rowSpan};`,
        text: cell.key || ''
      });
      div.appendChild(c);
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
        console.warn('diagram-panel: unknown panel type', panel.type);
        return el('div');
    }
  }

  function renderEntries(entries) {
    const stack = el('div', { class: 'diagram-entries-stack' });
    for (const e of entries) {
      const row = el('div', { class: 'diagram-entry-row' },
        el('span', { class: 'entry-key', text: e.key }),
        el('span', { class: 'entry-arrow', text: '→' }),
        el('span', { class: 'entry-label', text: e.isGroup ? e.label + ' …' : e.label })
      );
      stack.appendChild(row);
    }
    return stack;
  }

  function render(payload, container) {
    const root = container || document.querySelector('.overlay-custom-body[data-renderer="diagram"]');
    if (!root) return;
    while (root.firstChild) root.removeChild(root.firstChild);
    const grid = el('div', { class: 'diagram-panel-grid' });
    for (const panel of (payload.panels || [])) {
      grid.appendChild(renderPanel(panel));
    }
    grid.appendChild(renderEntries(payload.entries || []));
    root.appendChild(grid);
  }

  window.overlayRenderers = window.overlayRenderers || {};
  window.overlayRenderers.diagram = render;
})();
