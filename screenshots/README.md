# Screenshots

Images used by the main `README.md`. They are generated from app-rendered icons and snapshots
so no real paths or personal folder names appear in the docs.

| File               | Shows                                                     | How it was made                    |
| ------------------ | --------------------------------------------------------- | ---------------------------------- |
| `hero.png`         | FolderForge folders plus an external ICNS icon.             | App exports composed with `magick`.|
| `main-window.png`  | The full app: sidebar tree, preview, Fill inspector.       | `--ui-snapshot --tab fill`         |
| `sidebar-tree.png` | The sidebar with nesting and indent guides.                | Cropped from `main-window.png`.    |
| `fill-image.png`   | Image Fill mode with placement controls.                   | Cropped from `--tab fill --image`. |
| `icon-overlay.png` | Overlay controls on top of an image fill.                  | Cropped from `--tab icon --image`. |
| `icns-fill.png`    | External ICNS applied as the whole folder icon.             | Cropped from `--image file.icns`.  |
| `add-folders.png`  | The Add Folders sheet: depth, exclusions, match preview.   | `--ui-snapshot --view sheet`       |
| `presets.png`      | The built-in presets.                                     | `--contact-sheet`                  |

## Regenerating

The demo folders live in `/tmp/Showcase` so no real paths or personal folder names appear in a
screenshot. Build it, style it, then shoot:

```bash
BIN="$(swift build --show-bin-path)/FolderForge"
D=/tmp/Showcase
ART=/tmp/folderforge-readme-gradient.png
ICON=dist/FolderForge.app/Contents/Resources/AppIcon.icns

magick -size 1200x760 gradient:'#66D9FF-#FF7A45' \
  \( -size 900x570 radial-gradient:'rgba(255,255,255,0.95)-rgba(255,255,255,0)' \) -gravity northwest -geometry +70+20 -compose screen -composite \
  \( -size 720x520 radial-gradient:'#FFD36E-#1B1028' \) -gravity southeast -geometry +0+0 -compose overlay -composite \
  "$ART"

for d in "Clients/Acme Corp" "Clients/Acme Corp/2026 Contracts" "Clients/Northwind" \
         "Code/api-server" "Code/web-app" "Code/web-app/src" \
         "Design/Brand" "Archive/2024" "Photos/Iceland"; do mkdir -p "$D/$d"; done

"$BIN" --apply "$D/Clients" --preset Work
"$BIN" --apply "$D/Code" --recursive --preset Code
"$BIN" --apply "$D/Design" --recursive --preset Design
"$BIN" --apply "$D/Archive" --recursive --preset Archive
"$BIN" --apply "$D/Photos" --preset Photos
"$BIN" --apply "$D/Photos/Iceland" --preset Travel

FOLDERS=$(find "$D" -type d ! -path "$D" | sort | paste -sd, -)
"$BIN" --ui-snapshot main-window.png --width 1080 --height 700 --folders "$FOLDERS" --tab fill --image "$ART" --symbol sparkles --finish raised
"$BIN" --ui-snapshot add-folders.png --width 560 --height 780 --view sheet --path "$D"
"$BIN" --ui-snapshot icon-overlay-source.png --width 1080 --height 700 --tab icon --folders "$FOLDERS" --image "$ART" --symbol wand.and.sparkles --finish raised
"$BIN" --ui-snapshot icns-fill-source.png --width 1080 --height 700 --tab fill --folders "$FOLDERS" --image "$ICON"
"$BIN" --contact-sheet presets.png --columns 8 --cell 180

magick main-window.png -crop 480x1120+0+0  +repage sidebar-tree.png
magick main-window.png -crop 724x1400+1436+0 +repage fill-image.png
magick icon-overlay-source.png -crop 724x1400+1436+0 +repage icon-overlay.png
magick icns-fill-source.png -crop 724x1400+1436+0 +repage icns-fill.png
magick presets.png     -crop 1440x808+0+0  +repage presets.png
```

`--ui-snapshot` needs an unlocked screen — the window server won't composite a window while
the Mac is locked. It needs no Screen Recording permission.
