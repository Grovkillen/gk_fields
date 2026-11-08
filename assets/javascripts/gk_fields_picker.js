// gk_fields picker: for whoever may administer texts, an icon at every text on the page that can be administered; the
// icon leads to that text. A text is found by its entry, never by its words: turning the picker on asks for the page
// again with the picker's parameter, and on that page each name a translated reader or a list field's label gave ends
// with an invisible mark carrying its entry's number (GkFields::Picker). The page gives the entries' keys in the
// numbers' order (window.gkFieldsPickerConfig, drawn by PickerHooks); this script takes every mark out of the page and
// puts the icon where a mark stood inside #main. A mark in an attribute, a field's value, an option or the window's
// title is only taken out. Turning the picker off hides the icons and takes the parameter out of the address; on again
// shows them. Whoever has no row in gk_gui_stuff's three-dot menu on this page gets a small button at the bottom right.
(function () {
  var cfg = window.gkFieldsPickerConfig;
  var gk = window.gkFields = window.gkFields || {};
  if (!cfg || gk.picker) return;
  var PARAM = cfg.param, keys = cfg.keys || [], taken = !!cfg.taken, on = taken, menu = !!cfg.menu, btn = null, icons = [];
  // a whole mark (start, at least one bit, stop) is the only one that gets an icon; a mark cut short (a title
  // shortened after the reader gave it) is only taken out of the page's text; a lone U+2063 a person wrote
  // is left as it is, and never taken out of an attribute or a field's value
  var MARK = /\u2063([\u200B\u200C]+)\u2064/g, CUT = /\u2063[\u200B\u200C]+/g;
  function strip(s) { return s.replace(MARK, ''); }
  function stripText(s) { return strip(s).replace(CUT, ''); }
  // The button at the bottom right of the page, for whoever has no row in a three-dot menu on this page. It never
  // covers the page's content: it stands in the page's flow after everything else, in a row of its own at the
  // end, never fixed over the window, so no line of a page, a panel or a form (also one held in view, or one in the
  // middle of the page) ever lies under it, and it moves nothing above it.
  function button() {
    btn = document.createElement('a');
    btn.href = '#'; btn.id = 'gk-fields-picker'; btn.textContent = cfg.label; btn.title = cfg.title;
    btn.setAttribute('role', 'button'); btn.setAttribute('aria-pressed', on ? 'true' : 'false'); btn.setAttribute('aria-label', cfg.title);
    btn.style.cssText = 'display:inline-block;padding:3px 8px;font-size:0.85em;border:1px solid var(--oc-gray-5,#adb5bd);border-radius:3px;background:var(--oc-gray-0,#f8f9fa);';
    if (on) btn.style.fontWeight = 'bold';
    btn.addEventListener('click', function (e) { e.preventDefault(); toggle(); });
    var row = document.createElement('div');
    row.className = 'gk-fields-picker-row';
    row.style.cssText = 'display:flex;justify-content:flex-end;clear:both;margin:8px;';
    row.appendChild(btn);
    document.body.appendChild(row);
  }
  function icon(key) {
    var a = document.createElement('a'); a.className = 'gk-fields-pick';
    if (window.GkGui && GkGui.icon) a.appendChild(GkGui.icon('edit', '\u270E', 12)); else a.textContent = '\u270E';
    a.href = cfg.find + '?key=' + encodeURIComponent(key); a.title = cfg.title;
    // in the middle of the text's line wherever the text is (a value, a cell, a title), and as big as the text
    a.style.cssText = 'margin-inline-start:3px;font-size:0.8em;text-decoration:none;display:inline-flex;align-items:center;vertical-align:middle;line-height:1;';
    var svg = a.querySelector('svg'); if (svg) { svg.style.inlineSize = '1em'; svg.style.blockSize = '1em'; }
    if (!on) a.style.display = 'none';
    icons.push(a);
    return a;
  }
  // every mark out of the page; the icon where a mark of a known entry stood in a text of #main
  function take() {
    var main = document.getElementById('main') || document.body;
    var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT), nodes = [], n; // gk-r17 P4r: walks the text only for the picker's own invisible mark (U+2063 to U+2064) that Picker wrote into names on this page; no word, language or order of core is read
    while ((n = w.nextNode())) { if (n.nodeValue.indexOf('\u2063') >= 0) nodes.push(n); } // gk-r17 P4r: looks for the picker's own invisible mark, never for core's words
    nodes.forEach(function (n) {
      var p = n.parentElement, s = n.nodeValue;
      if (p && p.tagName === 'TEXTAREA') { n.nodeValue = strip(s); return; }
      if (!p || !main.contains(p) || /^(SCRIPT|STYLE|OPTION|TITLE)$/.test(p.tagName)) { n.nodeValue = stripText(s); return; }
      var frag = document.createDocumentFragment(), last = 0, m;
      MARK.lastIndex = 0;
      while ((m = MARK.exec(s))) {
        frag.appendChild(document.createTextNode(s.slice(last, m.index).replace(CUT, '')));
        var key = keys[parseInt(m[1].replace(/\u200B/g, '0').replace(/\u200C/g, '1'), 2)];
        if (key) frag.appendChild(icon(key));
        last = MARK.lastIndex;
      }
      frag.appendChild(document.createTextNode(s.slice(last).replace(CUT, '')));
      p.replaceChild(frag, n);
    });
    // a mark never stays where it is read or sent: attributes, a field's value, the window's title
    document.querySelectorAll('*').forEach(function (el) {
      Array.prototype.forEach.call(el.attributes, function (at) { if (at.value.indexOf('\u2063') >= 0) at.value = strip(at.value); });
      if ((el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') && el.value && el.value.indexOf('\u2063') >= 0) el.value = strip(el.value);
    });
    if (document.title.indexOf('\u2063') >= 0) document.title = stripText(document.title); // gk-r17 P4r: takes the picker's own invisible mark out of the window's title; core's title text is kept as it is
  }
  function address(add) {
    var u = new URL(window.location.href);
    if (add) u.searchParams.set(PARAM, '1'); else u.searchParams.delete(PARAM);
    return u.toString();
  }
  function toggle() {
    // a page without the marks is asked for again with them
    if (!taken) { window.location.href = address(true); return; }
    on = !on;
    icons.forEach(function (a) { a.style.display = on ? 'inline-flex' : 'none'; });
    if (btn) { btn.style.fontWeight = on ? 'bold' : ''; btn.setAttribute('aria-pressed', on ? 'true' : 'false'); }
    try { window.history.replaceState(window.history.state, '', address(on)); } catch (e) { /* the address stays */ }
  }
  if (taken) { take(); window.addEventListener('load', take); }
  document.addEventListener('keydown', function (e) { if (e.altKey && e.shiftKey && (e.key === 'T' || e.key === 't')) { e.preventDefault(); toggle(); } });
  // the menu's row (gk_gui_stuff runs it as an action; its script is in the page's head). A page without a
  // three-dot menu has no row once the page is in, and gets the button.
  if (window.GkGui && window.GkGui.actions) window.GkGui.actions.fields_picker = function () { toggle(); };
  if (!menu) button();
  else window.addEventListener('load', function () { if (!document.querySelector('[data-gk-gui-stuff-menu-key="fields_picker"]')) button(); });
  gk.picker = { toggle: toggle };
})();
