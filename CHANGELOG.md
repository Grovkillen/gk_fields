# Changelog

All notable changes to GK Fields are documented in this file.

## 1.02.000 (2026-11-15)

### Changed

* Requires GK GUI Stuff 1.05.000 or later; a candidate of that version counts, and GK GUI Stuff's own gate must be open. Otherwise the settings page says why in one line: GK GUI Stuff is missing, too old, or installed but not active. The required version is named only when the installed one is too old, and the line for not active links to GK GUI Stuff's own settings page. The line names the pages, the menus and the API of the plugin as what is not active, and says that protection and traces hold all the same. Meanwhile the pages, the menus, what GK Fields draws on other pages and the REST API are closed: no field format Date and time, no translated names, no corrected Redmine texts, no Texts button, no sections of a layout and no hooks, and what GK Fields registers in other plugins in order to draw is not registered (the reason places in GK Records, the row in GK GUI Stuff's three-dot menu and the row in its personal menu, the appearances of field types). A field of the format Date and time is then what Redmine makes of an unknown format. Other plugins that ask GK Fields about texts are answered as if it were not installed: the languages are Redmine's default language and English, a text has only its own words, and nothing is saved. The migrations run all the same, and the stored settings are posted back when the settings page is saved.
* Protection and the registered permissions hold without GK GUI Stuff. The fields of a layout's section whose level a person does not reach stay left out of the issue page and the issue form, which Redmine then draws itself without sections; this holds while GK Access is installed and the function Layouts is on. The three functions stay declared in GK Records, which answers for them as they are stored. The levels a stored layout names stay marked as in use in GK Access, so such a level cannot be removed there meanwhile. The five permissions and the two OAuth scopes stay registered, so a role saved meanwhile keeps them; they open nothing while the pages are closed.
* What GK Fields draws and translates with (the core patches for that, the field format and the readers of other plugins' models) is set up once every plugin has loaded, at the end of each preparation, instead of while GK Fields itself loads.
* The sections of a layout, on the issue page and in the issue form, are GK GUI Stuff's groups: the heading folds the section, a section the layout folds starts folded, and the level above the lowest is a pill in its role (the first step warning, every step above it alarm). The lock of such a section is an icon whose popover says who sees it, and "You see" is a help icon whose popover names the levels.
* A proposal's state is GK GUI Stuff's pill with a dot (waiting info, approved saved, rejected alarm), and what came since the person was here last is GK GUI Stuff's flag New; the coloured line at the start of the row and the tinted row are gone.
* The counts after Proposed texts, Show only what lacks a translation, the filters of Proposed texts and the headings of a pasted text's review are GK GUI Stuff's count.
* Sending a proposal and saving a layout use GK GUI Stuff's button with a reason; the reason stands on its own line under the box's buttons. A proposal's reason is required without GK Records, as before.
* Delete in the row menu of the layouts is confirmed in GK GUI Stuff's upper layer instead of the browser's confirmation.
* Copy on the exchange page is GK GUI Stuff's copy with its whisper; the line beside the link is gone.
* When GK Access is missing the settings page says so in GK GUI Stuff's banner.
* The changelog on the settings page is drawn by GK GUI Stuff.
* The Texts button's look and the pencils' are in a stylesheet of their own, with colours through GK GUI Stuff's roles; the page gives the button its settings as a JSON element.
* The scripts that stood in the pages (the issues a layout's preview can use, the tab shown in Translations, Copy, the languages' chooser) are files of their own, and every colour in the stylesheets goes through a role of GK GUI Stuff.
* The texts in the lists of Translations start where their column starts through the stylesheet instead of an inline style.
* README: the lowest versions of the other GK plugins are no longer listed.

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
