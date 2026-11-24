# Good morning: what MenuBento needs from you

Everything is built, committed and pushed to `claude/menubar-manager`.
MenuBento is **not running** right now, and your menu bar is exactly as it
was: same 26 items, same order (checked with a before/after diff). I reset
MenuBento's own preferences after testing.

## 1. Signing identity (decide, about 1 minute)

Builds are **ad-hoc signed** now, as you asked overnight. The catch: every
rebuild changes the signature, so macOS forgets the Accessibility and
Screen Recording grants.

**Heads-up:** a certificate called **"MenuBento Dev"** already exists in
your login keychain. I created it earlier, after you picked "Yes, create
it" in the question dialog, and before your overnight message arrived. It
is trusted for code signing only. Its private key files were deleted from
the scratchpad straight away. I haven't used it in the build, and I didn't
remove it while you were away.

**To use it** (recommended, so you grant permissions once):

```bash
cd ~/Capital-menubar/menubento        # or wherever this branch is checked out
security find-identity -v -p codesigning   # should list "MenuBento Dev"
echo 'SIGN_ID = MenuBento Dev' > sign.mk   # untracked, read by the Makefile
make run
```

The first build signed with it may ask "codesign wants to access key
'MenuBento Dev'". Click **Always Allow**.

**Or remove it** and stay ad-hoc:

```bash
security delete-identity -c "MenuBento Dev" ~/Library/Keychains/login.keychain-db
```

**To make one from scratch** (on another Mac, say), this is what I ran:

```bash
mkdir -p /tmp/mbcert && cd /tmp/mbcert
cat > cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = MenuBento Dev
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cert.cnf
PW=$(openssl rand -hex 12)
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -name "MenuBento Dev" -out id.p12 -passout pass:$PW
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P $PW -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem   # password prompt
rm key.pem id.p12
```

## 2. Grant Accessibility (needed for most features)

After `make run`, Settings opens on **Permissions**. Click **Grant…**,
then switch on MenuBento in System Settings → Privacy & Security →
Accessibility.

It's needed for: listing items, moving them (drag in Settings, groups,
presets), the Cells fill and the menus island, and clicking items in the
MenuBento bar. Hiding and showing, hover, spacers, dividers and the tint
or glow look all work without it.

With ad-hoc signing you'll need to remove MenuBento from that list and add
it again after each rebuild (see 1).

## 3. Screen Recording (optional)

Only for pictures of hidden items in the MenuBento bar. Without it the bar
shows each app's icon and name. "In the menu bar" reveal mode needs no
Screen Recording at all.

## 4. Decide: Hidden Bar

**Hidden Bar is running** (the `‹` chevron near Outlook). On macOS 27 it
can't hide anything: its separator is 5002 pt wide, and macOS drops items
longer than about half the screen. It also uses ⌘-drag positions, so two
managers can fight. I left it alone. If you switch to MenuBento, quit Hidden
Bar and remove it from Login Items.

## 5. Decide: defaults

- Clicking the icon reveals hidden items **in place**. Prefer the drop-down
  **MenuBento bar**? Settings → Hidden items.
- **Show on hover** is off by default; **auto-rehide** is on (3 s).
- The menu bar look is **off** until you switch it on in Appearance.
  Suggested start: Aurora, Split, Tint 35 %, glow on.
- On first launch MenuBento's items sit at the far left of your status
  items, so nothing is hidden until you move items into Hidden.

## What I verified overnight

All on your Mac, with `screencapture` crops of the menu bar. Features that
need Accessibility or Screen Recording were tested by launching the binary
from Terminal, which already has both:

- Hide / show / ⌥-click show everything, with a throwaway probe item.
- The macOS 27 rules behind the hiding approach. Single items over about
  2546 pt are dropped, and items left of the centre aren't drawn, so the
  separator is sized to just under half the screen.
- Moving items: Settings context menu, and drag and drop between columns.
- Groups: hide parks only the group's items; show puts each one back.
- Presets: save, then apply after a manual change, restored exactly. None
  of your items moved (diff of all 26).
- The MenuBento bar: opens under the icon, shows real pictures, and
  clicking one reveals it in place, presses it and auto-rehides.
- Hover reveal, plain-until-hovered and auto-rehide.
- Appearance: Tint / Cells / Glow only, whole / island / split shapes,
  Aurora, Neon and Sunset themes.
- Spacers and dividers, including the glow divider.
- The move planner: `menubento-cli plantest` passes.

## Blocked or not verified

- **The app's own permission prompts and grants.** I couldn't click
  through System Settings for you. Everything behind them was tested via
  the Terminal launch described above.
- **Reduce Motion.** It's handled in code (drift, glow and divider
  animation freeze), but I didn't flip your system setting to test it.
- **"Behind the bar" layer.** Your menu bar is opaque, so it shows
  nothing here (a test window confirmed it). "Over the bar" is the default.
- **Multiple displays, notched MacBooks.** No such hardware here.
- **"Launch at login."** Not toggled, so I didn't add a login item for you.
- **Your own app layout.** I didn't move any of your real items into
  Hidden. That's your call.
