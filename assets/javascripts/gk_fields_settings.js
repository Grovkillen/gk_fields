// GK Fields, the Configure page. The languages to offer get GK GUI Stuff's searchable chooser (GkGui.selectSearch): the
// list marked data-gk-fields-select-search stays in the form, hidden by the chooser, and is what is saved. What is
// missing for the layouts (gk_access) is GK GUI Stuff's banner, from the words in data-gk-fields-banner and its level in
// data-gk-fields-banner-level. Both found by their own data attributes.
(function () {
  'use strict';

  function start() {
    var G = window.GkGui;
    document.querySelectorAll('select[data-gk-fields-select-search]').forEach(function (sel) {
      if (sel.dataset.gkGuiSs) return;
      G.selectSearch.enhance(sel);
    });
    document.querySelectorAll('[data-gk-fields-banner]').forEach(function (mark) {
      if (mark.dataset.gkFieldsShown) return;
      mark.dataset.gkFieldsShown = '1';
      G.banner.show({ key: 'gk_fields_access_missing', text: mark.getAttribute('data-gk-fields-banner'),
                      level: mark.getAttribute('data-gk-fields-banner-level') || 'warning', where: false });
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
