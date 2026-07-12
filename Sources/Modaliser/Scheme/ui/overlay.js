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
// entries, walk, footer, cols, keyCh} payload.
//
// data: { rootSegments: ["my-server","Global"], path: ["Windows"], entries: [...] }
// path entries are group labels resolved from the navigation key chars,
// not the raw keys — so the breadcrumb reads "Global » Windows" not
// "Global » w".
window.overlayRenderers.list = function(data) {
  // Toggle the .walk class on the root .overlay element so users can
  // theme the persistent mode indicator distinctly. The flag is sent by
  // push-overlay-update on every change so descending into / popping out
  // of a Walk updates the styling live.
  var root = document.querySelector('.overlay');
  if (root) {
    if (data.walk) {
      root.classList.add('walk');
    } else {
      root.classList.remove('walk');
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

  // Update entry list — the key-column width comes through as data.keyCh and
  // is promoted to the --entry-key-ch custom property the .overlay-entries
  // rule reads. The column count is CSS-intrinsic (an auto-fit grid), so there
  // is no --overlay-cols. Mirrors the data-attr emitted by
  // render-overlay-default for the initial paint.
  var ul = document.querySelector('.overlay-entries');
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
      // A leaf declaring 'next gets a \u21bb marker BEFORE the label (kept
      // in sync with render-entry in overlay.scm). Leading position keeps
      // the markers in a consistent column across rows; trailing position
      // would drift with label width.
      if (e.isNext) {
        displayLabel = '<span class="entry-next-marker">\u21bb</span>' + displayLabel;
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

// Block renderer registry. The live-list block renderers (window-list.js,
// iterm-panes, iterm-tabs, window-diagram) register themselves here under their
// type; the panel-grid renderer's renderPanelList looks them up to draw a
// panel's embedded live list. (The whole-overlay block-list renderer that also
// drew from this registry was removed in the flag-day deletion.)
window.overlayBlockRenderers = window.overlayBlockRenderers || {};

// Panel-grid renderer — handles {type:"panel-grid", cols?, layout?, panels:[…]}
// payloads, the layout DSL's lowered `screen` / `open` (ADR-0011). Each
// panel is a banded card: a header label, key rows, and an optional embedded
// live list. A panel's `span` (narrow|wide|full) maps to a CSS grid column
// span. By default base.css packs the cards as masonry (display: grid-lanes)
// so a short panel tucks under a shorter neighbour; an authored `layout:"grid"`
// sets data-layout="grid" to switch to deterministic aligned placement. The
// column count is JS aspect-balanced (balancePanelGridColumns) by default; an
// authored `cols` hard-pins it; base.css's auto-fit is the pre-JS fallback.
//
// Bootstrap passes the `.overlay-custom-body` div as `container` (chrome is
// already baked into the initial HTML); push-updates pass none, so we refresh
// the breadcrumb/walk/footer chrome ourselves — same contract as the blocks
// renderer above.
window.overlayRenderers['panel-grid'] = function(data, container) {
  if (!container) updateOverlayChrome(data);
  var root = container
    || document.querySelector('.overlay-custom-body[data-renderer="panel-grid"]');
  if (!root) return;
  while (root.firstChild) root.removeChild(root.firstChild);

  // Loose region (bare-loose-rows-k23): a screen's loose top-level rows,
  // folded top-level opens, and loose bare blocks render header-less directly
  // on the body tint, ABOVE the panel grid — like the Settings overlay's
  // Edit/Reload rows. Empty array → no .panel-loose block at all. The element
  // is appended now (so loose blocks lay out and contribute to the overlay's
  // max-content width) but its rows are columnized LAST, once the grid is
  // balanced and the overlay width has settled (loose-row-columns-k33).
  var loose = data.loose || [];
  var looseEl = loose.length ? renderLoose(loose) : null;
  if (looseEl) root.appendChild(looseEl);

  // The masonry grid of real panel cards. Empty array (a loose-only screen)
  // → no .panel-grid, so nothing renders an empty box.
  var panels = data.panels || [];
  if (panels.length) {
    var grid = document.createElement('div');
    grid.className = 'panel-grid';
    // Authored packing mode; absent, base.css packs as masonry. Only
    // data-layout="grid" has a CSS override, so 'masonry stays the default.
    // Set BEFORE balancing so the measured lane/aligned heights reflect it.
    if (typeof data.layout === 'string') {
      grid.setAttribute('data-layout', data.layout);
    }
    for (var i = 0; i < panels.length; i++) {
      grid.appendChild(renderPanel(panels[i]));
    }
    root.appendChild(grid);
    // Column count: an authored `cols` hard-pins the track count and skips
    // measurement (the only override). Absent, balance the grid in JS — pick
    // the count whose rendered shape is closest to the target ratio, superseding
    // base.css's auto-fit default (responsive-columns-k30). The grid must
    // already be in the DOM (appended above) so the balance can measure it, and
    // it runs before notifyResize → the native panel is sized/shown from the
    // balanced layout, so there's no visible column-count flash.
    if (typeof data.cols === 'number') {
      grid.style.setProperty('--panel-grid-cols', String(data.cols));
    } else {
      balancePanelGridColumns(grid, panels);
    }
  }

  // Columnize the loose rows LAST — now the panel grid is balanced and any
  // loose blocks are laid out, the width:max-content overlay has settled to its
  // content width W = max(Wp, Wb). layoutLooseColumns reads that and fills it
  // with each row-run's own column count (loose-row-columns-k33).
  if (looseEl) layoutLooseColumns(looseEl);

  notifyResize();
};

// Target overall width:height for the panel grid — a fixed JS policy constant
// (the user declined exposing it; responsive-columns-k30). The balance picks
// the column count whose shape lands closest to this.
var PANEL_GRID_TARGET_RATIO = 1.4;

// balancePanelGridColumns — choose --panel-grid-cols by aspect balance instead
// of CSS auto-fit (which always maximizes the track count, so three short panels
// render as three columns where two read better). Revives the spirit of the
// deleted overlay aspect search, but measures the real layout per candidate
// rather than predicting it: for each plausible column count we pin the tracks,
// force a synchronous reflow, read the grid's rendered (width,height), and keep
// the count minimizing |width/height − target|. Measuring (vs predicting lane
// packing) lets the browser do the real masonry/aligned packing, span placement,
// and content-height layout for us — so it's correct under both the masonry
// default and layout:"grid", and honours wide/full spans for free.
//
// No visible flash: style writes don't paint until the JS task yields, and
// reading offset* forces layout but not paint, so only the final count is ever
// rendered — even on a live push-update while the overlay is already showing.
function balancePanelGridColumns(grid, panels) {
  var cs = getComputedStyle(grid);
  // Fall back to base.css's inline defaults (these tokens aren't set in :root).
  var minWidth = parseFloat(cs.getPropertyValue('--panel-min-width')) || 184;
  var gap = parseFloat(cs.getPropertyValue('--panel-gap')) || 10;
  var maxWidth = parseFloat(cs.getPropertyValue('--panel-grid-max-width')) || 760;
  // Upper bound 1: how many min-width tracks fit under the grid's max-width cap.
  var maxFit = Math.floor((maxWidth + gap) / (minWidth + gap));
  // Upper bound 2: the panels' own column demand. A wide panel wants two tracks,
  // a narrow one; a full panel spans the row at any count, so it adds none. More
  // columns than this only ever creates empty tracks (which inflate width and so
  // are never the argmin anyway, but bounding the loop keeps it honest).
  var demand = 0;
  for (var i = 0; i < panels.length; i++) {
    var span = panels[i] && panels[i].span;
    demand += (span === 'full') ? 0 : (span === 'wide') ? 2 : 1;
  }
  var maxCols = Math.max(1, Math.min(maxFit, demand || 1));
  if (maxCols <= 1) {
    grid.style.setProperty('--panel-grid-cols', '1');
    return;
  }
  var bestCols = 1, bestDelta = Infinity;
  for (var c = 1; c <= maxCols; c++) {
    grid.style.setProperty('--panel-grid-cols', String(c));
    var w = grid.offsetWidth, h = grid.offsetHeight;   // forces sync layout
    if (h <= 0) continue;
    var delta = Math.abs((w / h) - PANEL_GRID_TARGET_RATIO);
    if (delta < bestDelta) { bestDelta = delta; bestCols = c; }
  }
  grid.style.setProperty('--panel-grid-cols', String(bestCols));

  // Font-swap guard: the bundled IBM Plex faces load async, so a bootstrap
  // balance can measure fallback-font metrics and lock a stale count. If the
  // faces aren't ready yet, re-balance once they settle — the panels reflow on
  // swap regardless, so the corrected count rides that same reflow rather than
  // adding a separate flash. fonts.ready resolves immediately when already
  // loaded; the recursion ends after one pass (status === 'loaded' then), and
  // the isConnected guard skips a grid a later render has replaced.
  if (document.fonts && document.fonts.status !== 'loaded') {
    document.fonts.ready.then(function() {
      if (grid.isConnected) { balancePanelGridColumns(grid, panels); notifyResize(); }
    });
  }
}

// renderLoose — the header-less loose region: a flex column of bare blocks and
// row-grid runs, declaration order preserved. Each item is distinguished by
// shape (matching loose-region-json in overlay.scm): a block carries `type` and
// is drawn full-width via the SAME renderPanelList path the panels use (CSS
// strips the inset chrome inside .panel-loose); a row carries `key` and is drawn
// with the canonical renderPanelRow.
//
// Consecutive rows are grouped into a .panel-loose-rows RUN (loose-row-columns-
// k33) — a block closes the open run, so a row-run is exactly the rows between
// two blocks (or the whole loose region when there are none). layoutLooseColumns
// later columnizes each run to fill the established width; blocks stay full-width
// siblings. Grouping by run (not the whole region) keeps declaration order: a
// diagram / s,r / list screen renders block, then the s,r grid, then block.
function renderLoose(items) {
  var block = document.createElement('div');
  block.className = 'panel-loose';
  var run = null;   // the open row-run, or null between/around blocks
  for (var i = 0; i < items.length; i++) {
    var item = items[i];
    if (item && item.type) {
      run = null;   // a full-width block ends the current run
      block.appendChild(renderPanelList(item));
    } else {
      if (!run) {
        run = document.createElement('div');
        run.className = 'panel-loose-rows';
        block.appendChild(run);
      }
      run.appendChild(renderPanelRow(item));
    }
  }
  return block;
}

// Loose-row min track width — the natural width of one key-row (keycap + arrow +
// label), narrower than a 184px panel card, so loose rows columnize into MORE
// columns than the panels to fill the same width. A fixed JS/CSS policy paired
// with --loose-row-min-width / --loose-row-col-gap in base.css (the CSS fallbacks
// match these, so a theme can retune in one place). responsive-columns-k30.
var LOOSE_ROW_MIN_WIDTH = 168;
var LOOSE_ROW_COL_GAP = 16;

// layoutLooseColumns — fill the loose region's row-runs with their own column
// count. The overlay is width:max-content, so it has ALREADY resolved to the
// content width W = max(Wp, Wb) — Wp the balanced panel grid, Wb the widest
// loose block — by the time this runs (after the grid is balanced). We read that
// settled width off the loose region (its runs are still single-column, so they
// don't drive it), then give each run floor((W+gap)/(minW+gap)) columns, capped
// by the run's own row count so a short run doesn't over-spread into 1-row
// columns. Each run is pinned to W px so its multi-column grid can FILL W but
// never inflate the overlay past the width the rest established (its 1fr tracks
// fill W; they don't drive it). Mirrors balancePanelGridColumns' measure-then-set
// + fonts.ready guard.
function layoutLooseColumns(looseEl) {
  var runs = looseEl.querySelectorAll(':scope > .panel-loose-rows');
  if (!runs.length) return;   // blocks-only loose region — nothing to columnize

  var cs = getComputedStyle(looseEl);
  var padL = parseFloat(cs.paddingLeft) || 0;
  var padR = parseFloat(cs.paddingRight) || 0;
  var W = looseEl.clientWidth - padL - padR;   // forces sync layout
  if (W <= 0) return;
  var minW = parseFloat(cs.getPropertyValue('--loose-row-min-width')) || LOOSE_ROW_MIN_WIDTH;
  var gap = parseFloat(cs.getPropertyValue('--loose-row-col-gap')) || LOOSE_ROW_COL_GAP;
  var fit = Math.max(1, Math.floor((W + gap) / (minW + gap)));

  for (var i = 0; i < runs.length; i++) {
    var run = runs[i];
    var n = Math.max(1, Math.min(run.childElementCount, fit));
    run.style.width = W + 'px';
    run.style.setProperty('--loose-row-cols', String(n));
  }

  // Font-swap guard, mirroring balancePanelGridColumns: the bundled IBM Plex
  // faces load async and the panel grid re-balances on swap (its own guard), so
  // W can change. Re-run once the faces settle so the runs keep filling the
  // grid's final width. The grid's guard, registered first (balance runs before
  // this), re-balances before this re-reads the updated width — fonts.ready's
  // .then callbacks fire in registration order.
  if (document.fonts && document.fonts.status !== 'loaded') {
    document.fonts.ready.then(function() {
      if (looseEl.isConnected) { layoutLooseColumns(looseEl); notifyResize(); }
    });
  }
}

// renderPanel — one banded card: header + key rows + optional live list.
function renderPanel(panel) {
  var card = document.createElement('div');
  // A panel marked `bare` (it hosts a window-diagram — diagram-bare-panel-k22)
  // gets the .panel--bare modifier so base.css drops the card fill/border/shadow
  // and the list inset, letting the diagram's transparent empty cells reveal
  // the body tint. The panel stays a .panel grid item, so span/masonry placement
  // is unchanged.
  var className = 'panel panel-span-' + (panel.span || 'narrow');
  if (panel.bare) className += ' panel--bare';
  card.className = className;

  // A panel authored with a falsy label — (panel #f …) — is headerless: draw no
  // banded header band at all (an empty .panel-head would still claim its own
  // padding strip). The title is config-controlled, so a layout diagram drops
  // its "Layout" eyebrow by dropping the label, not by renderer policy
  // (window-diagram-polish-k31).
  if (panel.label) {
    var head = document.createElement('div');
    head.className = 'panel-head';
    head.textContent = panel.label;
    card.appendChild(head);
  }

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

// renderPanelRow — the canonical key-row renderer: keycap / arrow / label.
// (Previously shared via window.overlayRenderRow with the which-key block's JS;
// that block was removed in the flag-day deletion, so this local renderer — the
// former fallback — is now the single source. The row keeps the .wk-row class
// the panel CSS targets.)
function renderPanelRow(row) {
  var displayKey = row.key === ' ' ? '␣' : row.key;
  var labelClass = row.isGroup ? 'entry-label group-label' : 'entry-label';
  var labelText = row.isGroup ? (row.label + ' …') : row.label;
  var labelNode = document.createElement('span');
  labelNode.className = labelClass;
  if (row.isNext) {
    var marker = document.createElement('span');
    marker.className = 'entry-next-marker';
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

// Shared chrome update — breadcrumb, walk flag, footer. Used by the list,
// blocks, and panel-grid renderers so navigation depth changes look
// consistent regardless of which renderer is showing the body.
function updateOverlayChrome(data) {
  var root = document.querySelector('.overlay');
  if (root) {
    if (data.walk) root.classList.add('walk');
    else root.classList.remove('walk');
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
// emits data-key-ch on .overlay-entries; promote it to the --entry-key-ch
// custom property the CSS reads. Mirrors the update-path code in the list
// renderer above. Until this runs, the base.css fallback (2ch) covers the
// first-paint window. (Column count is CSS-intrinsic — no data-cols.)
function applyOverlayEntryProps() {
  var ul = document.querySelector('.overlay-entries');
  if (!ul) return;
  var keyCh = ul.dataset.keyCh;      // data-key-ch (kebab → camel)
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
