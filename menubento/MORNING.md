# MenuBento: status and what's left for you

_Last updated 24 Nov 2026._

## Where things stand

- **Installed** at `/Applications/MenuBento.app` (version 1.0.0, with its
  own icon), signed with your "MenuBento Dev" certificate via `sign.mk`.
  It's running from there, and it's the copy Launch at login opens.
- **Permissions:** Accessibility and Screen Recording are granted. The
  grants are stored against the certificate, not one build, so the move to
  /Applications and later reinstalls keep them. No prompt appeared after
  installing.
- **Your layout:** MenuBento's icon is next to Control Centre and every
  other item is hidden. One click shows them, another hides them. The first
  install put MenuBento's own items back at their default place (macOS
  treats a copy in a new folder as a new app); I restored your layout with
  Hide everything (reset layout) and checked it against a screenshot from
  before the install.
- **Hidden Bar** was quit and moved to the Bin (you asked). Drag it out of
  the Bin if you ever want it back.
- **Launch at login** is on; Settings → Hidden items shows the status.

## Nothing you need to do

Everything is set up. Things that might come up:

| If | Then |
|---|---|
| The bar looks muddled | Right-click the icon → **Hide everything (reset layout)** |
| macOS asks for Accessibility again | Settings → Permissions → **Grant…** (clears MenuBento's stale entry, asks once). Details in the README |
| You update MenuBento | `make install` in `menubento/` |
| codesign asks to use the "MenuBento Dev" key | Click **Always Allow** |
| You want to give it to someone | `make dmg` → `dist/MenuBento.dmg` |

## Decisions still open

- **BentoBox** (the "Box" item) is still running. It doesn't seem to be a
  menu bar hider, so I left it alone.
- **The look:** Appearance is on (Neon, outline fill). Change it in
  Settings → Appearance.

## Not verified

- Reduce Motion (handled in code, your system setting wasn't changed).
- Multiple displays and notched MacBooks (no such hardware here).
- Installing from the dmg on another Mac.
