// The site's one script: a lightbox for the screenshots, and the mirror switch on
// the pages that have one. Nothing here talks to anything; the pages work without it.
(function () {
  // The mirror: a HUD is read in a reflection. Any .stage with a button inside it.
  document.querySelectorAll('.stage').forEach(function (stage) {
    var btn = stage.querySelector('.flip-btn');
    var note = stage.querySelector('.flip-note');
    if (!btn) return;
    var offText = btn.getAttribute('data-off') || 'Show it as the windshield reflects it';
    var onText = btn.getAttribute('data-on') || 'Show it as designed';
    var offNote = note ? note.getAttribute('data-off') : '';
    var onNote = note ? note.getAttribute('data-on') : '';
    btn.addEventListener('click', function () {
      var on = stage.getAttribute('data-mirrored') !== 'true';
      stage.setAttribute('data-mirrored', on ? 'true' : 'false');
      btn.setAttribute('aria-pressed', on ? 'true' : 'false');
      btn.textContent = on ? onText : offText;
      if (note) note.textContent = on ? onNote : offNote;
    });
  });

  var dlg = document.getElementById('lightbox');
  if (!dlg || typeof dlg.showModal !== 'function') return;
  var img = document.getElementById('lbImg');
  var cap = document.getElementById('lbCap');
  document.querySelectorAll('button.zoom').forEach(function (b) {
    b.addEventListener('click', function () {
      var src = b.querySelector('img');
      var fig = b.closest('figure');
      img.src = src.currentSrc || src.src;
      img.alt = src.alt;
      var c = fig && fig.querySelector('figcaption');
      cap.textContent = c ? c.textContent : '';
      dlg.showModal();
    });
  });
  dlg.addEventListener('click', function (e) {
    if (e.target === dlg) dlg.close();
  });
})();
