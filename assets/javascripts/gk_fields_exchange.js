// GK Fields, Copy and paste: Copy puts the texts of the field #gk_fields_yaml on the clipboard through GK GUI Stuff's
// copy, whose whisper at the link says it is done (the words in the link's data-gk-fields-copied). The link is found
// by its own class, on a click anywhere in the page, so the script may stand in the page's head.
(function () {
  'use strict';

  document.addEventListener('click', function (e) {
    var link = e.target.closest('a.gk-fields-copy-yaml'), area = document.getElementById('gk_fields_yaml');
    if (!link || !area) return;
    e.preventDefault();
    window.GkGui.copy(area.value, link.getAttribute('data-gk-fields-copied'), link);
  });
})();
