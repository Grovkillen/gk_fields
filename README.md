# GK Fields

GK Fields adds a custom field format for a date and time, lets the names Redmine keeps as a single text (trackers, statuses, priorities, roles, categories, custom fields and list values) be shown in each user's language, lets an instance correct Redmine's own texts per language, and divides an issue's head into sections with layouts. The text as it is written is never changed by a translation: it stays the key that is stored, validated, imported and returned by the API.

## Features

- A custom field format "Date and time". The value is stored in UTC with minute precision, edited with the browser's date and time input in the time zone of the person who saves it, and shown in the viewer's time zone using Redmine's date and time format. It can be filtered with Redmine's date operators, on the viewer's own day, and sorted.
- Translations of the names and descriptions of trackers, statuses, priorities and other enumerations, roles, issue categories and custom fields, and of the values of list custom fields. Other GK plugins can register their own texts on the same page.
- Translations are applied when pages are shown and in emails (in the recipient's language). They are not applied on the pages where the names are edited, in imports, or outside a request. The REST API returns the text as it is written unless the request asks for a language with `lang=`.
- A Translations page with a tab per kind of text, a filter for what lacks a translation, and a direct save of translations.
- Copy and paste: the texts for one language are exported as YAML to be translated elsewhere (for example in an AI chat) and pasted back. A review shows what is new, changed, unchanged or skipped before anything is saved.
- Redmine's texts: a tab on the Translations page where Redmine's own texts are overridden per language without changing Redmine's files. It shows Redmine's English and Redmine's text in the language, takes an override that is shown instead, can mark a text as right as it is, filters what is missing or the same as the English, searches keys and texts, offers starting suggestions for Swedish that apply only when taken and saved, and gives the overrides of a language as a locale file. The overrides are applied through an I18n backend placed in front of Redmine's. An override may use only the variables Redmine's text has, and only an administrator may write HTML. Redmine's settings among its texts (the CSV encoding and separators, the PDF fonts, the first day of the week and the text direction) are changed only by an administrator, and only to a value Redmine can use; they are never counted as missing.
- Changed texts: a log of every change with the text before and after, who changed it and when.
- Proposals: a change to the text as it is written, or to a list value, is sent as a proposal with a reason that a reviewer approves or rejects. The proposal form shows how many stored values would change. Approving a list value change updates the stored values. Nobody but an administrator can approve their own proposal.
- Five permissions, granted through a role in any project: Translate texts that are set up, Propose a changed original text, Propose a changed list value, Review proposed texts, and Override Redmine's texts. Administrators have them all.
- The Texts button: an optional row "Show the texts that can be changed" in GK GUI Stuff's three-dot menu, or a button at the bottom right on a page without that menu (shortcut Alt+Shift+T), that puts a pencil next to each text that can be translated or changed, leading to that text.
- The number of proposals waiting for review is shown to reviewers in the top menu, or in GK GUI Stuff's personal menu when that plugin is installed.
- Layouts (Administration > Layouts), an optional function that needs GK Access: an administrator divides an issue's attributes into sections per tracker, and optionally per status, project and page (the issue page or the form), written as JSON, checked when saved and previewed with an issue before saving. A section has a title per language, one or two columns, can start folded, and has a level from GK Access: it is drawn only for a person whose role's ceiling reaches the level, and above the lowest level it shows a lock and the level. A section is never less protected than its fields. A line "You see" names the levels the reader sees fields in. Fields a layout does not name are shown in a folded section Other, and a field the reader may not see is never shown. A custom field type can offer several appearances, and a layout chooses one per page and for small screens. Every layout saved or removed is kept as an event with GK Records; a layout saved without a change is none. With the function off, the menu entry and the pages are gone and an issue is drawn as in Redmine; saved layouts stay untouched.

REST API (with Redmine's REST web service enabled), JSON, by the same rules as the pages and never showing more:

- Whoever may translate: `GET /gk_fields/translations.json` gives the texts that can be translated with their translations, every tab or one (`type=`), all or only those that lack a translation (`missing=1`). `PUT /gk_fields/translations.json` with `{ "translations": [ { "key": "<key>", "texts": { "<language>": "<text>" } } ] }` saves translations; an unknown key or language, or a text that is not a string or a number, is refused and nothing is saved. A key given twice is saved once, with the later texts winning per language; an empty text removes the translation.
- Everyone logged in: `GET /gk_fields/translations/changes.json`, the latest changes as on Changed texts.
- Proposals: `GET /gk_fields/translations/proposals.json` gives the latest 200, newest first, of all proposals to a reviewer and of one's own to everyone else, as the page Proposed texts does. `POST /gk_fields/translations/proposals.json` with `{ "proposal": { "key", "after_text", "reason" } }` proposes, for whoever may propose that kind of text. `POST /gk_fields/translations/proposals/<id>/decide.json` with `{ "verdict": "approve" }` or `"reject"` and an optional `"note"` decides, for a reviewer; nobody but an administrator approves her own.
- Whoever may override Redmine's texts: `GET /gk_fields/translations/core.json?lang=<language>` gives Redmine's texts in a language (with `filter=missing`, `own` or `proposals`, `q=`, `offset` and `limit`, at most 100). `PUT /gk_fields/translations/core.json` with `{ "lang": "<language>", "texts": [ { "key", "value", "confirmed" } ] }` saves overrides; a value or mark not given stays as it is, and a value that is not a string or a number, a mark that is not true or false, or a text the rules refuse (a variable Redmine's text does not have, HTML or one of Redmine's settings from someone who is not an administrator, a setting with a value Redmine cannot use) is refused and nothing is saved.
- Administrators, when the Layouts function is on: `GET /gk_fields/layouts.json` and `/gk_fields/layouts/<id>.json`, `POST /gk_fields/layouts.json` and `PUT /gk_fields/layouts/<id>.json` with `{ "layout": { "tracker_id", "status_id", "project_id", "scope", "layout" }, "reason": "<text>" }` (the layout as JSON text or as an object; `scope` is `show` or `edit`; `reason` stands beside `layout`, not inside it, is kept on the layout's event with GK Records, and is required when the reason place Layout, save requires it, otherwise 422), and `DELETE /gk_fields/layouts/<id>.json`. A layout that does not hold is refused with the same messages as the page.
- Errors are answered as Redmine's own: 422 with the messages, 403 and 404.
- OAuth (Redmine 6.1 and later): a token reads with the scope "Read texts, translations, proposals, Redmine's texts and layouts (API scope)" and changes with "Change texts, translations, proposals, Redmine's texts and layouts (API scope)". The scopes only limit a token; who may do something stays the same, and a token also needs the permission itself as a scope. The scopes are checked with GK Compat 1.01.000 or later, and then an administrator's token needs only the scope: it counts as an administrator in every rule, also for proposing, for approving her own proposal and for HTML and Redmine's settings among Redmine's texts. Without it, or with an older GK Compat, the scopes are not checked and an administrator's token counts as an administrator only with Redmine's scope Administration, as in Redmine. Sessions and API keys work as before.

## Requirements

- Redmine 6.0.0 or later
- Ruby: the version your Redmine runs on
- PostgreSQL

This plugin is developed and tested on Windows 11 with PostgreSQL only. That is a deliberate choice made for the maintainer's own convenience: the production system and the whole toolchain run there, and supporting other platforms and databases would cost time without adding anything for our own use. The Ruby code avoids needless Windows or PostgreSQL specific constructs, so it may well run on Linux, but that is untested and not supported. Every table stores its times with the time zone (`timestamptz`), so PostgreSQL is required.

Required GK plugins:

- GK Access (`gk_access`): the levels of the layouts' sections and whether a person sees a level. Without GK Access the plugin starts and everything but the layouts works: the menu item and the pages of Layouts are not there and an issue is drawn as in Redmine. The configure page says that GK Access is missing and what works without it.

Optional GK plugins:

- GK Records (`gk_records`): the switches for the plugin's three functions, Translations, the Texts button and Layouts (its register of functions), the reason fields on proposals and layouts, and the history of changes as events. Without GK Records all three functions are off and cannot be turned on, and the plugin uses its own reason field for proposals; the Date and time field format and the translations and overrides already stored still work.
- GK GUI Stuff (`gk_gui_stuff`): the page Administration > Functions where the three functions are switched on, and the row of the Texts button in the three-dot menu. Without GK GUI Stuff the functions cannot be switched on.
- GK Icons (`gk_icons`): the icon in the administration menu.
- GK Workflow Rules (`gk_workflow_rules`): when a list value change is reviewed, the number of rules that mention the value is shown, when the installed GK Workflow Rules has the method for it (`GkWorkflowRules.rules_naming`). With a version without the method, or without GK Workflow Rules, only the stored values are counted, and the rules are checked by hand.
- GK Compat (`gk_compat`): Redmine's color variables in Redmine 6.0 and 6.1, and from 1.01.000 the OAuth scopes of the REST API.
- GK Scenarios (`gk_scenarios`): test scenarios for the plugin; no effect in production.

## Installation

The plugin directory must be named `gk_fields` (it is the plugin id).

1. Unpack the release package into Redmine's `plugins` directory, so that the plugin lives in `plugins/gk_fields/`.
2. Run the migrations from the Redmine root:

   ```
   bundle exec rake redmine:plugins:migrate RAILS_ENV=production
   ```

3. Restart Redmine.

To uninstall, roll back the migrations and then remove the `plugins/gk_fields/` directory. Rolling back removes the plugin's tables and its settings, and makes every custom field of the format Date and time a text field, with its values kept as text in UTC (for example `2026-11-04 08:30:00Z`); installing the plugin again does not turn them back. A saved query that compares such a field with a date (on or after, on or before, between), also as a project's default query or in a block on My page, fails once the field is text: the rollback names each such query without changing it, so change them before or right after uninstalling. A filter block of GK Queries with such a comparison is not named; check the blocks by hand. The rollback:

```
bundle exec rake redmine:plugins:migrate NAME=gk_fields VERSION=0 RAILS_ENV=production
```

## Configuration

Administration > Plugins > Configure next to GK Fields:

- The language the names are written in: a language code. That language needs no translation. Empty means Redmine's default language.
- Languages to offer: language codes separated by commas. Empty means Redmine's default language and English. The list applies to every GK plugin: other plugins read it with `GkFields.content_languages` (the language the names are written in first) and use `[Setting.default_language, 'en']` when GK Fields is not installed.

The Translations function, the Texts button and Layouts are declared in GK Records and switched on under Administration > Functions in GK GUI Stuff; all three are off in a new installation. The five permissions are set per role under Administration > Roles and permissions; they are global and in no project module.

## Usage

- Administrators create "Date and time" custom fields under Administration > Custom fields, like any other field format.
- Administrators reach the Translations page from the administration menu, next to Custom fields. Users who may translate or override Redmine's texts find Translations in the top menu.
- The Translations page links to Copy and paste, Changed texts and Proposed texts, and has the tab Redmine's texts last, for those who may override Redmine's texts.
- Users who may translate and propose changes use the Propose a change link next to a text on the Translations page. Users who may only propose reach the same link on the page for a text that the Texts button leads to, when both the Translations function and the Texts button are on; the Translations page itself needs Translate texts that are set up or Override Redmine's texts. Reviewers find waiting proposals under Proposed texts.
- Administrators write layouts under Administration > Layouts, next to Custom fields.

## Changelog

See CHANGELOG.md.

## License

GPL-2.0-or-later, the same license as Redmine. Copyright (C) 2026 Jimmy Westberg. See the LICENSE file for the full text.
