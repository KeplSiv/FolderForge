<div align="center">

<img src="screenshots/logo.png" width="72" height="72" alt="FolderForge logo">

# FolderForge

**A macOS folder icon designer.**
Pick a color, drop on a symbol, emoji, image or custom ICNS, and write it straight to your
folders — with a one-click path back to the originals.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-native-0071e3?style=flat-square)
![Dependencies](https://img.shields.io/badge/dependencies-none-success?style=flat-square)
![GUI + CLI](https://img.shields.io/badge/GUI%20%2B%20CLI-one%20binary-5E5CE6?style=flat-square)

[![Download DMG](https://img.shields.io/badge/Download-FolderForge.dmg-blue?style=flat-square&logo=apple)](https://github.com/KeplSiv/FolderForge/releases/latest/download/FolderForge.dmg)

![folders](screenshots/hero.png)

</div>

---

## Contents

|                                                       |                                                                 |
| ----------------------------------------------------- | --------------------------------------------------------------- |
| [Install](#install)                                   | [What you can change](#what-you-can-change)                     |
| [Quick start](#quick-start)                           | [How the recoloring works](#how-the-recoloring-works)           |
| [The sidebar](#the-sidebar)                           | [Command line](#command-line)                                   |
| [Adding a whole tree](#adding-a-whole-tree)           | [Keyboard shortcuts](#keyboard-shortcuts)                       |
| [Restore & undo](#restore--undo)                      | [Behavior & edge cases](#behavior--edge-cases)                  |
| [How the recoloring works](#how-the-recoloring-works) | [Permissions](#permissions) · [Storage](#where-things-are-kept) |

---

## Install

```bash
git clone <this repo> && cd Folder_Customization

./build.sh --install     # builds and copies to /Applications
./build.sh --run         # builds into ./dist and launches
./build.sh --zip         # also produces dist/FolderForge.zip to hand to someone
```

Requires **macOS 14+** and the Xcode command line tools (`xcode-select --install`).
No Xcode project, no package dependencies.

> [!NOTE]
> The app is **ad-hoc signed**, not notarized. The first time you open a copy that was
> _downloaded_ rather than built locally, macOS refuses the double-click — right-click the
> app, choose **Open**, and confirm once.

---

## Quick start

<!-- 📸 screenshots/main-window.png -->

![The main window](screenshots/main-window.png)

1. **Add folders** — four ways:
   - drag them into the sidebar
   - type or paste a path into the field at the bottom of the sidebar, press <kbd>↩</kbd>
   - <kbd>⌘O</kbd> opens the full **Add Folders** sheet (path entry, depth, exclusions)
   - <kbd>⇧⌘O</kbd> grabs whatever is selected in Finder
2. **Design the icon** in the inspector on the right.
3. Hit **Apply**.

Select nothing and Apply hits _every_ folder in the list; select some and it hits only those.
Every folder already carrying a FolderForge icon is loaded into the list automatically at
launch, so you can pick up where you left off.

---

## The sidebar

<!-- 📸 screenshots/sidebar-tree.png -->

![Sidebar tree](screenshots/sidebar-tree.png)

Folders imported recursively **nest under their parent** rather than piling up as a flat
list. Each nesting level draws a vertical guide, so one recursive import reads as one
connected group.

- Click **anywhere in the indent column** — the whole vertical strip, not just the chevron —
  to collapse or expand a branch.
- Everything arrives **expanded**; collapsing is yours to opt into.
- The header counts what's loaded: `Folders · 19`.
- Badges: 🪄 styled by FolderForge · 🖼️ has a custom icon from somewhere else · nothing = plain.
- <kbd>⌫</kbd> removes the selection from the list. Right-click a row for Reveal in Finder,
  Load This Folder's Style, Restore Original Icon, Remove from List.

Removed some folders and want them back? **Settings → Customized folders → Add Them All to
the List**.

---

## Adding a whole tree

<!-- 📸 screenshots/add-folders.png -->

![Add Folders sheet](screenshots/add-folders.png)

The Add Folders sheet takes a path — with `~`, tab-style completion and shortcuts to Home /
Desktop / Documents / Downloads — then asks two questions:

**How deep?** Pick an exact depth from the folder tree, or choose all levels. Plus whether
the root itself is included, so you can style just the children of `~/Clients` and leave
`~/Clients` alone.

**What to leave out?** Hidden dot-folders, bundles (`.app`, `.photoslibrary`, `.xcodeproj`),
symlinks, and any list of shell-glob name patterns. Defaults already skip `node_modules`,
`.git`, `Library`, `*.app` and friends.

It then shows the **exact tree** it's about to add — collapsible, with the same indent guides
as the sidebar — before you commit. A 2000-folder cap keeps a scan of `/` from running away.

---

## Restore & undo

**Restore** puts the original icon back — the real one, not an approximation. The first time
FolderForge touches a folder it snapshots whatever icon was already there, so a folder that
had a custom icon before gets _that exact icon_ returned, and a plain folder goes back to
plain.

- <kbd>⌥⌘Z</kbd> undoes the last batch apply.
- <kbd>⌥⌘C</kbd> / <kbd>⌥⌘V</kbd> copy and paste a design between folders.
- **Refresh Finder** nudges Finder when macOS is still showing a cached old icon.

> [!IMPORTANT]
> **Icons FolderForge didn't make can't be reverse-engineered into settings.** A custom icon
> on disk is just the final image — the tint, symbol and layout that produced it were never
> stored anywhere. FolderForge shows you the real icon, archives a copy before replacing it,
> and can import an external `.icns` as a complete replacement icon.

---

## What you can change

<!-- 📸 screenshots/inspector.png -->

![Inspector](screenshots/inspector.png)

<details open>
<summary><b>🎨 Color</b></summary>

Any color, or a two-color gradient at any angle. 60+ curated swatches and 10 gradient
presets. Tint strength blends back toward the stock macOS blue.

</details>

<details open>
<summary><b>⭐️ Icon — 300+ SF Symbols, emoji, text, images or custom ICNS</b></summary>

Searchable symbol browser by category, plus emoji, short text, images, or custom `.icns`
files. Drag and drop an ICNS or choose one from the picker to use it as the whole folder icon.
Regular images stay as artwork on the folder canvas, with size, opacity, rotation and free
positioning.

External downloaded `.icns` files apply as complete icons:

![External ICNS import](screenshots/icns-import.png)

The Hollow Knight Silksong example above is an external icon from
[macOSicons](https://macosicons.com/?icon=kVqQ3Xg6Co). FolderForge can import `.icns` files
from your Mac; you can make your own or download premade icons from sites like
[macOSicons](https://macosicons.com/) and [Icon-Icons](https://icon-icons.com/). Check each
icon's license before using it, especially for commercial or redistributed work. FolderForge
does not bundle or redistribute third-party icons.

<!-- 📸 screenshots/finishes.png -->

![Finishes](screenshots/finishes.png)

| Finish       | Looks like                                                     |
| ------------ | -------------------------------------------------------------- |
| **Engraved** | Carved into the folder face. Apple's own look — the default.   |
| **Tinted**   | Flat fill in a color you choose.                               |
| **Natural**  | Keeps the artwork's own colors. Use this for emoji and photos. |
| **Stamped**  | Dark ink pressed into the folder.                              |
| **Raised**   | Bright and glossy, floating above with a soft shadow.          |

Emoji and images carry their own colors, so picking one switches the finish to **Natural**
automatically — a masked finish would flatten them to white silhouettes. ICNS files are
applied as complete icons. Switching back to a symbol restores **Engraved**.

</details>

<details>
<summary><b>🎚️ Tune</b></summary>

Saturation, brightness, contrast, and five one-click looks: Vintage, Punchy, Pastel, Noir,
Neon.

</details>

<details>
<summary><b>📐 Shape</b></summary>

Start from any of the 15 stock macOS folder shapes, not just the plain one.

</details>

<details>
<summary><b>💾 Presets</b></summary>

Save anything you like as a preset. Presets export as `.folderstyle` files you can share, and
double-clicking one imports it.

</details>

---

## How the recoloring works

<details>
<summary><b>Why the results look native instead of painted</b></summary>

The stock macOS folder art is recolored with a `.color` blend, which replaces hue and
saturation while keeping the original luminosity — so every gradient, highlight and drop
shadow in Apple's artwork survives intact.

A `.color` blend alone can't make a folder darker or lighter, so a second pass matches the
folder's **HSB brightness** to the tint. Deliberately HSB brightness and not perceived
luminance: a fully saturated red has a luminance of 0.21, so matching luminance would render
`#FF375F` as a nearly black folder — which is not what anyone means when they pick that color.

Icons are rendered separately at 16, 32, 64, 128, 256, 512 and 1024 px rather than
downsampled from one master, so the glyph stays legible in Finder's list view.

</details>

---

## Command line

The same binary is a CLI. Useful for dotfiles and setup scripts:

```bash
FF=/Applications/FolderForge.app/Contents/MacOS/FolderForge

$FF --apply ~/Projects --preset Code
$FF --apply ~/Notes --color '#FF9F0A' --emoji 📓 --finish natural
$FF --reset ~/Projects

# every immediate subfolder of ~/Clients, leaving ~/Clients itself alone
$FF --apply ~/Clients --depth 1 --no-root --preset Work

# a whole tree, skipping build output — look before you leap
$FF --apply ~/Code --recursive --exclude 'node_modules,dist,build' --dry-run
$FF --apply ~/Code --recursive --exclude 'node_modules,dist,build' --preset Code

$FF --reset ~/Code --recursive

$FF --export icon.png --preset Ocean --size 1024
$FF --export icon.png --image CustomIcon.icns
$FF --iconset MyIcon.iconset --preset Ocean
$FF --contact-sheet all.png          # every built-in preset in one grid
$FF --list-presets
$FF --help
```

Every style flag from `--help` works with `--apply`, `--export` and `--iconset`.

<details>
<summary><b>Development aids (hidden, not in <code>--help</code>)</b></summary>

```bash
FolderForge --ui-snapshot out.png --width 900 --height 620 [--view main|sheet] [--tab color|icon|tune] [--overlay icns] [--icon file.icns]
FolderForge --debug-selection <folder...>
```

`--ui-snapshot` renders the interface at an exact size by ordering a real window far offscreen
and capturing its backing store — so layout can be checked at any size, including sizes larger
than the display. It needs an unlocked screen: the window server won't composite while the Mac
is locked. `--debug-selection` prints what the editor adopts as the selection moves, and needs
no screen at all.

</details>

---

## Keyboard shortcuts

| Shortcut                        | Does                             |
| ------------------------------- | -------------------------------- |
| <kbd>⌘O</kbd>                   | Add Folders sheet                |
| <kbd>⌥⌘O</kbd>                  | Browse for folders               |
| <kbd>⇧⌘O</kbd>                  | Add the current Finder selection |
| <kbd>⌘↩</kbd>                   | Apply                            |
| <kbd>⇧⌘⌫</kbd>                  | Restore original                 |
| <kbd>⌥⌘Z</kbd>                  | Undo last apply                  |
| <kbd>⌥⌘C</kbd> / <kbd>⌥⌘V</kbd> | Copy / paste style               |
| <kbd>⌘R</kbd>                   | Surprise me                      |
| <kbd>⌘S</kbd>                   | Save as preset                   |
| <kbd>⌫</kbd>                    | Remove selection from the list   |

<kbd>⌘Z</kbd> is deliberately left to the system, so every text field in the app keeps its
normal undo. **Undo Last Apply** is <kbd>⌥⌘Z</kbd>.

---

## Behavior & edge cases

<details>
<summary><b>Icons FolderForge didn't make</b></summary>

A custom folder icon on disk is **just the final image**, stored in the resource fork of a
hidden `Icon\r` file inside the folder. The tint, symbol, finish and layout that produced it
are not recorded anywhere — so for any icon FolderForge didn't create, **the editable
settings cannot be recovered**. External `.icns` files can still be imported as complete
replacement icons; they just don't become tint/symbol/finish layers.

| Folder state               | Sidebar badge | Preview shows                            |
| -------------------------- | ------------- | ---------------------------------------- |
| Styled by FolderForge      | 🪄 wand       | its saved design, loaded into the editor |
| Custom icon from elsewhere | 🖼️ photo      | the real icon, read off disk             |
| No custom icon             | none          | a plain stock folder                     |

The preview switches to your design the moment you change anything, so an existing icon never
gets in the way.

</details>

<details>
<summary><b>Nothing destroys an icon without a copy first</b></summary>

- **`OriginalIcons/`** — before the first change to a folder, whatever icon was there is
  snapshotted. **Restore** puts that exact icon back. Folders that had no custom icon get a
  zero-byte sentinel instead, so Restore knows to _clear_ rather than paint.
- **`RemovedIcons/`** — restoring a folder whose icon FolderForge never made means clearing it
  outright, with no snapshot to fall back on. A timestamped copy is archived here first
  (Settings → **Open Archive**), capped at the newest 25. Only _foreign_ icons are archived; an
  icon FolderForge generated is fully reproducible from the style in the ledger, so copying it
  on every reset would burn megabytes for nothing.

A failed restore **keeps** its snapshot and reports an error rather than clearing the folder.

Snapshots are LZW-compressed TIFFs keeping every representation bit-for-bit — ~8 MB for an
elaborate icon, far less for a normal one. They only exist for folders that already had a
custom icon, which is rare. Snapshots for folders since deleted or moved are pruned at launch
and on demand via Settings → **Clean Up Snapshots for Deleted Folders**. Pruning is
conservative: it only drops entries whose recorded path is gone, and never touches a snapshot
file that has no ledger entry.

</details>

<details>
<summary><b>Selection drives the editor</b></summary>

Selecting a folder loads whatever that folder _is_: a saved design loads into the editor, a
plain folder shows plain, and a **mixed** selection leaves the design alone — there's no single
truth to show.

Unsaved work is never silently discarded. If you're mid-design and select a folder that has a
saved style, your design is put on the style clipboard and a toast tells you to press
<kbd>⌥⌘V</kbd>. And ⌘-clicking a _second plain folder_ onto the selection deliberately does
**not** reset the editor — that's how you apply one design to several folders at once.

</details>

<details>
<summary><b>Apply and Restore with nothing selected</b></summary>

Both fall back to "every folder in the list". That's convenient for two folders and alarming
for two hundred, so when nothing is selected and the list holds more than one folder, you get a
confirmation naming the count.

Batches run asynchronously and yield between folders, so the progress bar actually draws and
**Stop** works. Run synchronously, a 2000-folder batch would block the main run loop start to
finish and the app would look hung.

</details>

<details>
<summary><b>Scanning rules</b></summary>

- The scan runs off the main thread, debounced ~200 ms. Typing a single `/` with "All levels"
  selected walks the entire disk; doing that synchronously on every keystroke froze the window.
- Breadth-first, so a shallow depth limit costs nothing and the 2000-folder cap truncates at the
  top of the tree rather than deep inside one branch.
- Exclusion patterns use `fnmatch` with `FNM_CASEFOLD`, so `*.APP` matches `MyApp.app` and
  `node_modules` matches `NODE_MODULES`. Patterns containing `/` match the full path with
  `FNM_PATHNAME`, so `*` won't leap across directory separators.
- Bundles (`.app`, `.photoslibrary`, `.xcodeproj`) are directories on disk but are skipped by
  default — customizing them is never what's meant.
- Symlinked directories are skipped by default. The 2000-folder cap is what stops a symlink
  cycle if you turn that off.
- The root folder you name is always included regardless of exclusion patterns — you asked for
  it explicitly. Use `--no-root` to leave it out.

</details>

<details>
<summary><b>Paths</b></summary>

`~` expands. A bare relative path is tried against the working directory first (what you'd
expect from the CLI) and then against home (what you'd expect typing `Projects` into the app).
Quoted and backslash-escaped paths pasted from a terminal are accepted.

</details>

<details>
<summary><b>Known limits</b></summary>

- Settings can't be recovered from an existing icon FolderForge didn't make.
- Icons are re-rendered at each size (16 → 1024), but the stock artwork being recolored tops out
  at whatever macOS ships.
- Multicolor SF Symbols render as a single-color mask; palette and hierarchical rendering modes
  aren't exposed.
- Ad-hoc signed, not notarized — a downloaded copy needs right-click → **Open** once.

</details>

---

## Permissions

Setting a folder icon means writing _inside_ that folder, so macOS asks for access the first
time you touch something in Desktop, Documents or Downloads. Grant it in
**System Settings › Privacy & Security › Files and Folders**.

Reading the Finder selection (<kbd>⇧⌘O</kbd>) goes through Apple Events and prompts separately,
under **Privacy & Security › Automation**. Everything else works without it.

---

## Where things are kept

```
~/Library/Application Support/FolderForge/
  presets.json      your saved styles
  applied.json      which design is on which folder
  OriginalIcons/    pre-first-change snapshots (+ .none sentinels)
  RemovedIcons/     foreign icons that were cleared
```

Deleting that directory loses your presets and the ability to restore exact original icons.
Folders themselves are unaffected; **Restore** falls back to the plain system folder.

---

## Project layout

```
Sources/FolderForge/
  App/        Entry (CLI vs GUI), AppState, App + menus
  Core/       Model, renderer, glyph rasterizer, disk I/O, presets, scanner, CLI
  UI/         ContentView, sidebar, preview, inspector, pickers, sheets
Resources/    AppIcon.svg — the app icon, in vector
Scripts/      svg2png.swift — rasterizes the icon at each iconset size
build.sh      Produces dist/FolderForge.app
screenshots/  Images used by this README
```

The app icon is rendered from `Resources/AppIcon.svg` at build time, once per iconset size
straight from the vector instead of downsampled from a single master, so 16 and 32 px stay
crisp. Edit the SVG and re-run `./build.sh` to change it.

`Core/IconRenderer.swift` has no UI dependencies and is driven entirely by a `FolderStyle`
value — which is why the CLI, the live previews and the applied icons can't drift apart. They
all call the same function.

<div align="center">

---

Built with SwiftUI. No dependencies, no telemetry, no network.

</div>
