// Overlay display server — receives data, renders DOM locally.

// Auto-resize the native panel to fit overlay content.
function notifyResize() {
  var el = document.querySelector('.overlay');
  if (el) {
    var h = el.offsetHeight;
    window.webkit.messageHandlers.modaliser.postMessage({type: "resize", height: h});
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

// Update overlay content with new entries and breadcrumb.
// data: { label: "Global", path: ["w"], entries: [{key, label, isGroup}, ...] }
function updateOverlay(data) {
  // Update breadcrumb header
  var header = document.querySelector('.overlay-header');
  if (header) {
    var segments = [data.label].concat(data.path || []);
    var html = '';
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) html += '<span class="breadcrumb-sep">&gt;</span>';
      html += escapeHtml(segments[i]);
    }
    header.innerHTML = '<span class="breadcrumb">' + html + '</span>';
  }

  // Update entry list
  var ul = document.querySelector('.overlay-entries');
  if (ul) {
    var html = '';
    var entries = data.entries;
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i];
      var displayKey = e.key === ' ' ? '\u2423' : escapeHtml(e.key);
      var labelClass = e.isGroup ? 'entry-label group-label' : 'entry-label';
      var displayLabel = e.isGroup ? escapeHtml(e.label) + ' \u2026' : escapeHtml(e.label);
      html += '<li class="overlay-entry">';
      html += '<span class="entry-key">' + displayKey + '</span>';
      html += '<span class="entry-arrow">\u2192</span>';
      html += '<span class="' + labelClass + '">' + displayLabel + '</span>';
      html += '</li>';
    }
    ul.innerHTML = html;
  }
  notifyResize();
}
