# Changelog

All notable changes to GK Fields are documented in this file.

## 1.01.000 (2026-11-08)

### Changed

* The Texts button finds a text by the thing it belongs to, no longer by matching words on the page. Turning it on loads the page again with `gk_fields_pick=1`; on that page each translatable name is marked where Redmine draws it, and the pencil leads to that exact text. Redmine's lists of trackers, statuses, enumerations, custom fields and roles get pencils too; their edit pages do not, so a name is never saved with a mark. Only a whole mark gets a pencil, and text a person wrote is left as it is. Turning it off hides the pencils without a reload.
* The REST API with `lang=` gives `name` and `name_lang` (and `description` and `description_lang`) wherever Redmine's API views write the name of a tracker, status, priority, activity, category, role or custom field. They are added while the JSON is built, and the finished response is no longer read and rewritten.
* The Translations link on Redmine's pages for trackers, statuses, roles, enumerations and custom fields is drawn through a hook at the top of the content (GK Core Stuff 1.02.000 or later). It no longer looks for the page's button row.
* The languages to offer on the Configure page use GK GUI Stuff's searchable chooser. Without GK GUI Stuff, the plain list is shown.
* The Texts button no longer fetches a list of texts. The page behind it (`gk_fields/translations/texts`) is gone; nothing else used it.
* The Texts button never covers the page's content: it stands at the bottom right of the page, in a row of its own after everything else, instead of being held over the window, so no line of a page, panel or form lies under it at any scroll position.

### Fixed

* The whisper after Copy on the exchange page of Translations stands at the link, not low in the middle of the window.

## 1.00.000 (2026-10-28)

* First release.
