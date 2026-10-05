# GhostBar

A tiny macOS menu bar icon hider. Click any empty space in the menu bar to hide or show your clutter icons. There's no chevron and nothing extra in the bar.

## How it works

GhostBar adds one thin divider to the menu bar. Any icon you ⌘-drag to the **left** of the divider is hidden when GhostBar collapses. The divider stretches to a huge width and pushes those icons off-screen. A global click monitor watches for clicks on empty menu bar space (not on app menus or icons) and toggles between hidden and shown.

## Build

Requires the Xcode command line tools (macOS 13+).

```bash
./build.sh
mv GhostBar.app /Applications/ && open /Applications/GhostBar.app
```

On first launch, grant **Accessibility** access (System Settings → Privacy & Security → Accessibility) so GhostBar can tell empty bar space apart from app menus. Without it, GhostBar falls back to only toggling on clicks in the right half of the screen.

## Usage

- **Click empty menu bar space:** hide or show icons
- **Right-click empty menu bar space:** settings (auto-hide delay, launch at login, quit)
- **⌘-drag icons** left of the divider to choose what gets hidden. Drag the divider all the way right to hide everything.

The app is ad-hoc signed. If you rebuild it, macOS may reset the Accessibility permission, so toggle it off and on again.
