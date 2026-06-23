// Overlay display server — receives data, renders DOM locally.

// Auto-resize the native panel to fit overlay content.
// Width is reported alongside height because .overlay is width:max-content,
// so it grows to fit the widest of breadcrumb / entry list. The native
// panel matches both dimensions, top-left anchored.
function notifyResize() {
  var el = document.querySelector('.overlay');
  if (el) {
    window.webkit.messageHandlers.modaliser.postMessage({
      type: "resize",
      height: el.offsetHeight,
      width: el.offsetWidth
    });
  }
}

// Observe content size changes
var _resizeObserver = new ResizeObserver(notifyResize);
document.addEventListener('DOMContentLoaded', function() {
  var el = document.querySelector('.overlay');
  if (el) _resizeObserver.observe(el);
  notifyResize();
});

function escapeHtml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

// Renderer registry. Libraries register additional renderers by
// assigning to window.overlayRenderers[TYPE]. The diagram renderer
// (lib/modaliser/diagram-panel.js) registers itself when loaded.
window.overlayRenderers = window.overlayRenderers || {};

// Built-in list renderer — handles the default {rootSegments, path,
// entries, sticky, footer, cols, keyCh} payload.
//
// data: { rootSegments: ["my-server","Global"], path: ["Windows"], entries: [...] }
// path entries are group labels resolved from the navigation key chars,
// not the raw keys — so the breadcrumb reads "Global » Windows" not
// "Global » w".
window.overlayRenderers.list = function(data) {
  // Toggle the .sticky class on the root .overlay element so users can
  // theme the persistent mode indicator distinctly. The flag is sent by
  // push-overlay-update on every change so descending into / popping out
  // of a sticky subgroup updates the styling live.
  var root = document.querySelector('.overlay');
  if (root) {
    if (data.sticky) {
      root.classList.add('sticky');
    } else {
      root.classList.remove('sticky');
    }
  }

  // Update breadcrumb header
  var header = document.querySelector('.overlay-header');
  if (header) {
    var segments = (data.rootSegments || []).concat(data.path || []);
    var html = '';
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) html += '<span class="breadcrumb-sep">»</span>';
      html += escapeHtml(segments[i]);
    }
    header.innerHTML = '<span class="breadcrumb">' + html + '</span>';
  }

  // Update footer markup — the Scheme side sends HTML (sigils wrapped
  // in <span class="sigil">) so the dynamic re-render path styles them
  // the same way as the initial paint. Backspace hint is omitted at the
  // root because it doesn't apply there (kept in sync with
  // footer-html-for-path in overlay.scm).
  var footer = document.querySelector('.overlay-footer');
  if (footer && typeof data.footer === 'string') {
    footer.innerHTML = data.footer;
    // Toggle the right-align modifier so navigating root → deep → root
    // swaps the class live. Mirrors the conditional class in
    // render-overlay-body.
    var atRoot = !data.path || data.path.length === 0;
    footer.classList.toggle('overlay-footer-root', atRoot);
  }

  // Update entry list — column count and key-column width come through
  // as data.cols and data.keyCh and are applied as CSS custom properties
  // the entries' .overlay-entries rule reads via var(--overlay-cols)
  // and var(--entry-key-ch). Mirrors the inline style emitted by
  // render-overlay-body for the initial paint.
  var ul = document.querySelector('.overlay-entries');
  if (ul && typeof data.cols === 'number') {
    ul.style.setProperty('--overlay-cols', String(data.cols));
  }
  if (ul && typeof data.keyCh === 'number') {
    ul.style.setProperty('--entry-key-ch', String(data.keyCh));
  }
  if (ul) {
    var html = '';
    var entries = data.entries;
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i];
      // e.key arrives as ready HTML from key-display-html in overlay.scm
      // (modifier glyphs wrapped in <span class="sigil-mod">), so it is
      // not escaped here \u2014 same trust model as data.footer.
      var displayKey = e.key === ' ' ? '\u2423' : e.key;
      var labelClass = e.isGroup ? 'entry-label group-label' : 'entry-label';
      var displayLabel = e.isGroup ? escapeHtml(e.label) + ' \u2026' : escapeHtml(e.label);
      // Sticky-target leaves get a \u21bb marker BEFORE the label (kept in
      // sync with render-entry in overlay.scm). Leading position keeps the
      // markers in a consistent column across rows; trailing position would
      // drift with label width.
      if (e.isSticky) {
        displayLabel = '<span class="entry-sticky-marker">\u21bb</span>' + displayLabel;
      }
      html += '<li class="overlay-entry">';
      html += '<span class="entry-key">' + displayKey + '</span>';
      html += '<span class="entry-arrow">\u2192</span>';
      html += '<span class="' + labelClass + '">' + displayLabel + '</span>';
      html += '</li>';
    }
    ul.innerHTML = html;
  }
  notifyResize();
};

// Block-list renderer — handles {type: "blocks", blocks: [{type, …}, …]}
// payloads. Each block in payload.blocks is rendered by looking up
// window.overlayBlockRenderers[block.type] and calling it with
// (block, blockContainer). Block renderers append their own DOM into
// their per-block container; the renderer here just builds the row of
// containers in source order. Containers carry a "block block-<type>"
// class so block-specific CSS can scope its styles.
window.overlayBlockRenderers = window.overlayBlockRenderers || {};

window.overlayRenderers.blocks = function(data, container) {
  // Update chrome (breadcrumb, sticky flag, footer) alongside the body.
  // The Scheme-side push includes these fields on every update so the
  // header/footer track the navigation depth — e.g. so the backspace
  // hint appears once the user descends into a nested block-list group.
  // The bootstrap path passes a `container` and skips chrome (initial
  // HTML already has it baked in by render-overlay-custom).
  if (!container) {
    updateOverlayChrome(data);
  }
  var root = container || document.querySelector('.overlay-custom-body[data-renderer="blocks"]');
  if (!root) return;
  while (root.firstChild) root.removeChild(root.firstChild);
  var list = data.blocks || [];
  for (var i = 0; i < list.length; i++) {
    var block = list[i];
    var bc = document.createElement('div');
    bc.className = 'block block-' + block.type;
    root.appendChild(bc);
    var fn = window.overlayBlockRenderers[block.type];
    if (fn) {
      try {
        fn(block, bc);
      } catch (e) {
        console.error('block ' + block.type + ' render failed', e);
      }
    } else {
      console.warn('overlay: no block renderer for', block.type);
    }
  }
  notifyResize();
};

// Panel-grid renderer — handles {type:"panel-grid", cols?, panels:[…]}
// payloads, the layout DSL's lowered `screen` / `open` (ADR-0011). Each
// panel is a banded card: a header label, key rows, and an optional embedded
// live list. A panel's `span` (narrow|wide|full) maps to a CSS grid column
// span; base.css lays the cards out with grid-auto-flow: dense so narrow
// tiles backfill around wide ones. The column count is CSS-intrinsic
// (auto-fit) unless the payload carries an authored `cols`.
//
// Bootstrap passes the `.overlay-custom-body` div as `container` (chrome is
// already baked into the initial HTML); push-updates pass none, so we refresh
// the breadcrumb/sticky/footer chrome ourselves — same contract as the blocks
// renderer above.
window.overlayRenderers['panel-grid'] = function(data, container) {
  if (!container) updateOverlayChrome(data);
  var root = container
    || document.querySelector('.overlay-custom-body[data-renderer="panel-grid"]');
  if (!root) return;
  while (root.firstChild) root.removeChild(root.firstChild);
  var grid = document.createElement('div');
  grid.className = 'panel-grid';
  // Authored column count pins the track count; absent, base.css auto-fits.
  if (typeof data.cols === 'number') {
    grid.style.setProperty('--panel-grid-cols', String(data.cols));
  }
  var panels = data.panels || [];
  for (var i = 0; i < panels.length; i++) {
    grid.appendChild(renderPanel(panels[i]));
  }
  root.appendChild(grid);
  notifyResize();
};

// renderPanel — one banded card: header + key rows + optional live list.
function renderPanel(panel) {
  var card = document.createElement('div');
  card.className = 'panel panel-span-' + (panel.span || 'narrow');

  var head = document.createElement('div');
  head.className = 'panel-head';
  head.textContent = panel.label || '';
  card.appendChild(head);

  var rows = panel.rows || [];
  if (rows.length) {
    var body = document.createElement('div');
    body.className = 'panel-rows';
    for (var i = 0; i < rows.length; i++) {
      body.appendChild(renderPanelRow(rows[i]));
    }
    card.appendChild(body);
  }

  // Embedded live list (window-list / iterm-panes / iterm-tabs): hand the
  // block off to its registered block renderer — the SAME path the blocks
  // renderer uses — so the list section reuses that block's markup + CSS.
  if (panel.list && panel.list.type) {
    card.appendChild(renderPanelList(panel.list));
  }
  return card;
}

// renderPanelRow — reuse which-key.js's renderRow (assigned to
// window.overlayRenderRow when that block's JS asset loads, which the layout
// DSL always pulls in transitively). Falls back to an identical local
// renderer so a panel grid still draws rows if which-key.js is absent — and
// so this stays the canonical row renderer once which-key.js is retired.
function renderPanelRow(row) {
  if (typeof window.overlayRenderRow === 'function') {
    return window.overlayRenderRow(row);
  }
  var displayKey = row.key === ' ' ? '␣' : row.key;
  var labelClass = row.isGroup ? 'entry-label group-label' : 'entry-label';
  var labelText = row.isGroup ? (row.label + ' …') : row.label;
  var labelNode = document.createElement('span');
  labelNode.className = labelClass;
  if (row.isSticky) {
    var marker = document.createElement('span');
    marker.className = 'entry-sticky-marker';
    marker.textContent = '↻';
    labelNode.appendChild(marker);
    labelNode.appendChild(document.createTextNode(labelText));
  } else {
    labelNode.textContent = labelText;
  }
  var keyNode = document.createElement('span');
  keyNode.className = 'entry-key';
  keyNode.innerHTML = displayKey;   // ready key-display-html (sigil spans)
  var arrowNode = document.createElement('span');
  arrowNode.className = 'entry-arrow';
  arrowNode.textContent = '→';
  var rowEl = document.createElement('div');
  rowEl.className = 'wk-row';
  rowEl.appendChild(keyNode);
  rowEl.appendChild(arrowNode);
  rowEl.appendChild(labelNode);
  return rowEl;
}

// renderPanelList — inset section wrapping an embedded live list, drawn by
// the block's own renderer from window.overlayBlockRenderers (e.g.
// window-list.js). Container carries the same "block block-<type>" classes
// the blocks renderer uses so the block's CSS scopes identically.
function renderPanelList(block) {
  var section = document.createElement('div');
  section.className = 'panel-list block block-' + block.type;
  var fn = window.overlayBlockRenderers && window.overlayBlockRenderers[block.type];
  if (fn) {
    try {
      fn(block, section);
    } catch (e) {
      console.error('panel-grid: list ' + block.type + ' render failed', e);
    }
  } else {
    console.warn('panel-grid: no block renderer for', block.type);
  }
  return section;
}

// Shared chrome update — breadcrumb, sticky flag, footer. Used by the list,
// blocks, and panel-grid renderers so navigation depth changes look
// consistent regardless of which renderer is showing the body.
function updateOverlayChrome(data) {
  var root = document.querySelector('.overlay');
  if (root) {
    if (data.sticky) root.classList.add('sticky');
    else root.classList.remove('sticky');
  }
  var header = document.querySelector('.overlay-header');
  if (header && Array.isArray(data.rootSegments)) {
    var segments = data.rootSegments.concat(data.path || []);
    var html = '';
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) html += '<span class="breadcrumb-sep">»</span>';
      html += escapeHtml(segments[i]);
    }
    header.innerHTML = '<span class="breadcrumb">' + html + '</span>';
  }
  var footer = document.querySelector('.overlay-footer');
  if (footer && typeof data.footer === 'string') {
    footer.innerHTML = data.footer;
    var atRoot = !data.path || data.path.length === 0;
    footer.classList.toggle('overlay-footer-root', atRoot);
  }
}

// Custom renderers send {type: TYPE, ...}; built-in payloads omit
// type. Both dispatch the same way: lookup by type, fallback to
// 'list'.
function updateOverlay(payload) {
  // Lookup by payload.type; fallback to the built-in list renderer.
  var fn = (payload && payload.type && window.overlayRenderers[payload.type])
    || window.overlayRenderers.list;
  fn(payload);
}

// On initial HTML load the custom body div carries data-renderer
// and data-payload — invoke the same dispatch so the first paint
// matches subsequent updates.
function bootstrapCustomBody() {
  var div = document.querySelector('.overlay-custom-body');
  if (!div) return;
  var type = div.getAttribute('data-renderer');
  var payloadStr = div.getAttribute('data-payload');
  if (!type || !payloadStr) return;
  try {
    var payload = JSON.parse(payloadStr);
    var fn = window.overlayRenderers[type];
    if (fn) fn(payload, div);
  } catch (e) {
    console.error('overlay: bootstrap failed', e);
  }
}

// Default-renderer counterpart to bootstrapCustomBody. The Scheme side
// emits data-cols / data-key-ch on .overlay-entries; promote them to
// the --overlay-cols / --entry-key-ch custom properties the CSS reads.
// Mirrors the update-path code in the list renderer above. Until this
// runs, base.css fallbacks (1 col, 2ch) cover the first-paint window.
function applyOverlayEntryProps() {
  var ul = document.querySelector('.overlay-entries');
  if (!ul) return;
  var cols = ul.dataset.cols;        // data-cols
  var keyCh = ul.dataset.keyCh;      // data-key-ch (kebab → camel)
  if (cols) ul.style.setProperty('--overlay-cols', cols);
  if (keyCh) ul.style.setProperty('--entry-key-ch', keyCh);
}

function bootstrapInitialRender() {
  bootstrapCustomBody();
  applyOverlayEntryProps();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', bootstrapInitialRender);
} else {
  bootstrapInitialRender();
}
