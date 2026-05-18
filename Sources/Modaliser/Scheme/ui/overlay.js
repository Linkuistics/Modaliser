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
      var displayKey = e.key === ' ' ? '\u2423' : escapeHtml(e.key);
      var labelClass = e.isGroup ? 'entry-label group-label' : 'entry-label';
      var displayLabel = e.isGroup ? escapeHtml(e.label) + ' \u2026' : escapeHtml(e.label);
      // Sticky-target leaves get a \u21bb marker after the label (kept in sync
      // with render-entry in overlay.scm). The marker is a child span so
      // base.css can style it independently of the surrounding label text.
      if (e.isSticky) {
        displayLabel += ' <span class="entry-sticky-marker">\u21bb</span>';
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

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', bootstrapCustomBody);
} else {
  bootstrapCustomBody();
}
