// GK Fields, the tabs of Translations: the tab shown is scrolled into view once the page is in. Each tab opens a page
// of its own, and core's row of tabs starts at the first tab. The row is found by its own id
// (#gk-fields-translations-tabs), never as the first div.tabs on the page; core's displayTabsButtons shows its arrows
// when the tabs do not fit.
(function () {
  'use strict';

  window.addEventListener('load', function () {
    var ul = document.querySelector('#gk-fields-translations-tabs ul'), a = ul && ul.querySelector('a.selected');
    if (!a) return;
    var li = a.parentNode;
    if (li.offsetLeft + li.offsetWidth > ul.clientWidth) { ul.scrollLeft = li.offsetLeft - 20; }
    if (typeof displayTabsButtons === 'function') displayTabsButtons();
  });
})();
