# Screenshots

Images used by the main `README.md`. They are generated from app-rendered icons and snapshots
so no real paths or personal folder names appear in the docs.

| File               | Shows                                                        | How it was made                         |
| ------------------ | ------------------------------------------------------------ | --------------------------------------- |
| `hero.png`         | FolderForge folders, image fills, and the app ICNS.          | App-rendered visual composite.          |
| `main-window.png`  | The full app with its Fill inspector and image overlay.      | `--ui-snapshot --view main --tab fill`  |
| `smart-style.png`  | Smart Style preview, shipped starter rules, and safe scope.  | `--ui-snapshot --view smart`            |
| `icns-fill.png`    | The rounded FolderForge ICNS as a complete folder icon.      | `--ui-snapshot --view main --icon ...`  |

## Regenerating

Use a temporary tree so no real paths or personal folder names appear in a screenshot:

```bash
./build.sh
BIN=dist/FolderForge.app/Contents/MacOS/FolderForge
DEMO=/tmp/FolderForge-readme-demo
ICON=dist/FolderForge.app/Contents/Resources/AppIcon.icns

mkdir -p "$DEMO/Projects/App" "$DEMO/Photos" "$DEMO/Archives"
touch "$DEMO/Projects/App/package.json" "$DEMO/Photos/photo.jpg" "$DEMO/Archives/readme.txt"

"$BIN" --ui-snapshot smart-style.png --view smart --width 1520 --height 1600 --path "$DEMO"
"$BIN" --ui-snapshot icns-fill.png --view main --width 1440 --height 900 --icon "$ICON"
```

`--ui-snapshot` needs an unlocked screen — the window server won't composite a window while
the Mac is locked. It needs no Screen Recording permission.
