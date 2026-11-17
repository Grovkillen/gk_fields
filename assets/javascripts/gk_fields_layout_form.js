// GK Fields, a layout's form: the issues a preview can use, as one writes. Those of the tracker, status and project
// chosen in the form (as they are now in the form, not as saved), from the layouts' own list (the address in the field's
// data-gk-fields-url), into the field's datalist. Without jQuery; the field and the list are found by their own ids.
(function () {
  'use strict';

  function start() {
    var input = document.getElementById('gk_fields_preview_issue_id'), list = document.getElementById('gk-fields-preview-issues');
    if (!input || !list || input.dataset.gkFieldsReady) return;
    input.dataset.gkFieldsReady = '1';
    var place = { tracker_id: 'gk_fields_layout_tracker_id', status_id: 'gk_fields_layout_status_id', project_id: 'gk_fields_layout_project_id' };
    var timer = null, last = null, seq = 0;
    function query(term) {
      var q = 'term=' + encodeURIComponent(term);
      Object.keys(place).forEach(function (k) { var el = document.getElementById(place[k]); if (el && el.value) q += '&' + k + '=' + encodeURIComponent(el.value); });
      return q;
    }
    function load(force) {
      var term = input.value.trim(), q = query(term);
      if (!force && q === last) return;
      last = q; clearTimeout(timer);
      timer = setTimeout(function () {
        var mine = ++seq;
        fetch(input.dataset.gkFieldsUrl + '?' + q, { credentials: 'same-origin', headers: { 'Accept': 'application/json' } })
          .then(function (r) { return r.ok ? r.json() : []; })
          .then(function (rows) {
            if (mine !== seq) return;
            list.textContent = '';
            (rows || []).forEach(function (row) { var o = document.createElement('option'); o.value = row.id; o.label = row.label; o.textContent = row.label; list.appendChild(o); });
          }).catch(function () { /* no suggestions this time */ });
      }, 200);
    }
    input.addEventListener('input', function () { load(false); });
    input.addEventListener('focus', function () { load(false); });
    Object.keys(place).forEach(function (k) {
      var el = document.getElementById(place[k]);
      if (el) el.addEventListener('change', function () { load(true); });
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
