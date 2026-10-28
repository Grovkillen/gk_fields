// Redmine's texts (GK Fields): a starting suggestion is put in its field only when asked, one at a time or all
// empty fields on the page at once. Nothing is saved before the form is saved.
(function () {
  'use strict';

  function take(button) {
    var input = document.getElementById(button.getAttribute('data-gk-fields-target'));
    if (!input) return null;
    input.value = button.getAttribute('data-gk-fields-text') || '';
    input.dispatchEvent(new Event('input', { bubbles: true }));
    return input;
  }

  document.addEventListener('click', function (event) {
    var one = event.target.closest('.gk-fields-core-take');
    if (one) {
      event.preventDefault();
      var input = take(one);
      if (input) input.focus();
      return;
    }
    var all = event.target.closest('.gk-fields-core-take-all');
    if (!all) return;
    event.preventDefault();
    document.querySelectorAll('.gk-fields-core-take').forEach(function (button) {
      var target = document.getElementById(button.getAttribute('data-gk-fields-target'));
      if (target && target.value === '') take(button);
    });
  });
})();
