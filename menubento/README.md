# MenuBento

A native macOS menu bar manager with the same kind of customisation as
DuoNotch: sections and groups, spacers and dividers (including ones that
match the glow), drag-to-reorder for other apps' items, a drop-down
"MenuBento bar" for hidden items, themes for the menu bar itself, and
named presets.

Plain Swift package, no Xcode project. It runs as an accessory app
(`LSUIElement`), so it has no Dock icon: you'll find it in the menu bar as
a 2×2 grid icon.

## Install

```bash
cd menubento
echo 'SIGN_ID = MenuBento Dev' > sign.mk   # once; see "Signing" below
make install
```

`make install` does a release build, quits the running copy (and waits
until it has really exited), replaces `/Applications/MenuBento.app` and
opens it. The first time, Settings opens on **Permissions**: grant
Accessibility (and Screen Recording if you want pictures in the MenuBento
bar). Then right-click the icon → **Hide everything (reset layout)** if you
want every item hidden straight away.

### Update

Pull the branch and run `make install` again. Your settings, layout and
permission grants carry over, as long as the signing identity stays the same.

### Share as a disk image

```bash
make dmg         # → dist/MenuBento.dmg: MenuBento.app plus an Applications link
```

Open it and drag MenuBento onto Applications. Signed with a self-made
certificate, so on another Mac the first launch needs right-click → Open.

### Uninstall

1. Right-click the MenuBento icon → **Quit MenuBento**.
2. Settings → **Hidden items** → turn off **Launch at login** first (or
   remove it later in System Settings → General → Login Items).
3. Delete `/Applications/MenuBento.app`.
4. Optional: `defaults delete com.hawkes.menubento` (settings, groups,
   presets), and remove MenuBento from System Settings → Privacy & Security
   → Accessibility and Screen & System Audio Recording (select it, click −).

Your other apps' items stay wherever they were last; ⌘-drag them back if
you want them elsewhere.

### Developing

```bash
make run         # debug build → dist/MenuBento.app, then launches it
make settings    # same, and opens Settings
make icon        # redraw Resources/AppIcon.icns (Scripts/make-icon.swift)
make cli         # the menubento-cli debugging tool
```

Run one copy at a time: the installed one and a `dist/` one would both add
items to the menu bar. `make run` and `make install` quit whichever is running.

### Signing

macOS ties Accessibility and Screen Recording grants to the app's code
signature. With `SIGN_ID` set in the untracked `sign.mk` (the "MenuBento
Dev" certificate in your login keychain), the grant is stored against that
certificate, so it survives rebuilds and reinstalls. Without it, builds are
ad-hoc signed and every build looks like a new app to macOS.

If codesign shows "codesign wants to access key 'MenuBento Dev'", click
**Always Allow** (enter your login password if asked).

### If macOS keeps asking for a permission

That means the entry in System Settings belongs to a different build (an
ad-hoc build, or one from another folder), so switching it on doesn't
apply to the copy that's running. Either:

- In MenuBento: Settings → **Permissions** → **Grant…**. MenuBento clears
  its own stale entry first, then asks once; switch it on and you're done.
- Or by hand: System Settings → Privacy & Security → **Accessibility**,
  select MenuBento, click **−**, then open MenuBento and grant it again. Do
  the same under **Screen & System Audio Recording** if needed. From
  Terminal, `tccutil reset Accessibility com.hawkes.menubento` does the
  same for MenuBento only.

## Using it

| Do this | To |
|---|---|
| Click the MenuBento icon | Show or hide the Hidden section (or open the MenuBento bar, if you chose that) |
| ⌥-click it | Show everything, including Always hidden |
| Right-click (or ⌃-click) it | Menu: groups, presets, add spacer/divider, Hide everything (reset layout), Settings, Quit |
| ⌘-drag any item | Move it yourself. Anything left of `‹` is hidden; anything left of `«` is always hidden |
| Rest the pointer just left of your visible items | Reveal hidden items (when "Show on hover" is on) |

### Settings

The settings window has a sidebar:

- **Menu bar items**: three columns (Visible, Hidden, Always hidden). Drag
  items between them, or up and down to reorder (top = left). Dropping
  performs the move in the real menu bar. Right-click an item to send it
  to another section or add it to a group.
- **Groups**: named sets of items with a one-click Shown/Hidden switch,
  also in the right-click menu. Hiding a group parks its items in Always
  hidden; showing it puts each one back in the section it came from.
- **Spacers & dividers**: spacers with an adjustable width; dividers as a
  line, thick line, dot or three dots, in a custom colour or "Match the
  glow" (the theme's glow colours, moving in step with the glowing edge).
- **Hidden items**: in place or MenuBento bar, show on hover, auto-rehide
  delay, pictures in the bar, and launch at login (with its current status:
  on, off, or waiting for approval in Login Items).
- **Appearance**: the themes (Black, Aurora, Sunset, Neon, Ocean, Forest,
  Lavender, Dusk, Custom three-colour), shape (whole bar, island, split),
  fill (Tint, Cells, Glow only), corner radius, travelling glow edge,
  shadow, "stay plain until hovered", animation speed. Reduce Motion
  freezes the drift and glow.
- **Presets**: save the current layout (order, sections, spacers and
  dividers, and optionally the look), then rename, overwrite, delete, or
  apply. Also under right-click → Presets.
- **Permissions**: what each permission is for, with a button to grant it.

## How it works (and what's different on macOS 27)

Experiments on this Mac (macOS 27.0, 5120×1440, no notch) found that the
menu bar works differently from the systems Ice and Hidden Bar were built for:

1. **Status items are no longer separate windows.** MenuBarAgent draws
   the whole bar as one window, so `CGWindowListCopyWindowInfo` can't see
   individual items. MenuBento reads them through Accessibility instead:
   each app's `AXExtrasMenuBar` lists its items with frames, titles and
   identifiers. System items (Wi-Fi, Battery, Focus and so on) are wrapped
   in an `AXGroup`; the child holds a stable `com.apple.menuextra.*`
   identifier.
2. **The 10 000-point spacer trick no longer works.** A status item longer
   than about half the screen width (2546 pt on a 5120 pt display) is simply
   dropped, so the items it was meant to push away stay put. This is
   why Hidden Bar's separator (5002 pt) hides nothing here.
3. **One separator can't push far enough.** At just under half the screen
   width, a separator only pushes hidden items to the middle of the bar,
   where they stay visible (or sit under a notch). So each separator has an
   invisible "booster" item immediately to its left. Together they're as
   long as the distance to the screen's left edge, split into two pieces
   that are each under the limit. MenuBento ⌘-drags the boosters back into
   place by themselves if you move the separators (needs Accessibility).

Moving items synthesises exactly what you would do: hold ⌘ and drag. The
pointer is put back afterwards. To rearrange, MenuBento keeps the longest
run of items already in the right relative order and moves only the
others, each next to a neighbour that's already in place. After each drag
it checks the result and retries with a small nudge if needed. Items
macOS keeps fixed (the clock and Control Centre) are never moved.

Hidden items aren't drawn at all, so pictures of them can only be taken
while they're revealed. MenuBento grabs the menu bar strip with
ScreenCaptureKit whenever hidden items are shown, and cuts it up by each
item's frame. The first time the bar opens it flashes them in for half a
second to do this.

The menu bar on this Mac is opaque, so a window *behind* it can't be seen.
The appearance overlay therefore sits just above the bar and ignores the
mouse. "Tint" is a see-through wash. "Cells" is solid colour with a dark
cut-out around every item and menu, so the icons stay crisp. "Behind the
bar" is still available for see-through menu bars.

## Permissions

| Feature | Needs |
|---|---|
| Hide/show, ⌥-click, hover, auto-rehide, ⌘-dragging yourself | nothing |
| Spacers and dividers, appearance (Tint, Glow only, island shape) | nothing |
| Listing items, moving them from Settings, groups, presets | Accessibility |
| Cells fill and the split shape's menus island (need item/menu frames) | Accessibility |
| Clicking an item in the MenuBento bar | Accessibility |
| Pictures of items in the MenuBento bar | Screen Recording (optional; app icons otherwise) |

MenuBento never reads other apps' windows, typing or data. Item names come
from the labels apps provide for VoiceOver.

## menubento-cli

A small tool for checking things from Terminal (which usually has
Accessibility already):

```bash
.build/debug/menubento-cli list              # every item with frame and identifier
.build/debug/menubento-cli plantest          # unit checks for the move planner
.build/debug/menubento-cli movetest          # ⌘-drags three throwaway items around
.build/debug/menubento-cli probe NAME 60     # a throwaway status item for 60 s
.build/debug/menubento-cli click X Y [option|right]
.build/debug/menubento-cli move X Y
.build/debug/menubento-cli cmddrag SOURCE-ID TARGET-ID
```

Running `dist/MenuBento.app/Contents/MacOS/MenuBento` directly from
Terminal gives MenuBento Terminal's permissions. That's handy for testing
before you grant the app itself.

## Layout

```
Sources/MenuBentoCore/      Accessibility scanner, ⌘-drag mover, move planner
Sources/MenuBento/App/      entry point, AppModel (state, moves, groups, presets), models
Sources/MenuBento/MenuBar/  our status items, right-click menu, hover / auto-rehide
Sources/MenuBento/Bar/      the MenuBento bar and item pictures
Sources/MenuBento/Appearance/  themes and glow (copied from DuoNotch), the overlay
Sources/MenuBento/Settings/    sidebar window and pages
Sources/MenuBento/Support/     colours and reorder helpers (copied from DuoNotch), permissions
Sources/menubento-cli/      debugging tool
Scripts/make-icon.swift     draws Resources/AppIcon.icns
```

Theme colours, the mesh-gradient drift, the glow, drag-to-reorder and the
sidebar layout are copied from DuoNotch, not linked: the two apps share
no code at build time.

## Known limits

- **Without Accessibility** the boosters can't be put in place, so hiding
  only pushes items towards the middle of the bar.
- **Item identity.** An app with several unlabeled items is told apart by
  position ("#0", "#1"), so after such an app reorders its own items a
  group or preset may pick the wrong one.
- **Pictures.** The bar's pictures are only as fresh as the last time the
  items were revealed. Use "Retake pictures" in Settings → Hidden items.
- **Other managers.** Running another menu bar manager (Hidden Bar, Ice,
  Bartender) at the same time can fight over positions.
- **Untested here.** Multiple displays, notched MacBooks, and the "Behind
  the bar" layer on a see-through menu bar haven't been checked yet.
