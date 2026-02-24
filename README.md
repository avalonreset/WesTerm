# BenjaminTerm

Windows-first, hacker-styled terminal distro powered by WezTerm.

BenjaminTerm keeps upstream WezTerm power, then adds quality-of-life workflows for fast coding sessions:
smart copy/paste behavior, paste undo, font/theme cycling, borderless mode, persistent preferences, and now
click-to-focus Windows notifications when your coding tool asks for input.

```text
   ___  _____  __   _____   __  ________  _______________  __  ___
  / _ )/ __/ |/ /_ / / _ | /  |/  /  _/ |/ /_  __/ __/ _ \/  |/  /
 / _  / _//    / // / __ |/ /|_/ // //    / / / / _// , _/ /|_/ /
/____/___/_/|_/\___/_/ |_/_/  /_/___/_/|_/ /_/ /___/_/|_/_/  /_/
```

## Screenshot Preview

![BenjaminTerm terminal preview](assets/icon/benjaminterm_screenshot.jpg)

## Why BenjaminTerm

- Primary target: Windows developer workflow.
- Secondary target: Linux friend-ready bootstrap distro.
- Sensible defaults out of the box:
  - Theme system: curated pure-black palette pool with shuffle-bag rotation (no repeats until bag exhaustion).
  - Font: `OCR A Extended` with robust fallbacks.
  - Shell (Windows): `pwsh.exe`.
- Minimal UI:
  - Tab bar off.
  - Borderless toggle hotkey.

## Signature Features

- Smart `Ctrl+C`:
  - If text is selected, copy it and clear selection.
  - If not selected, pass through real `Ctrl+C` (interrupt behavior).
- Smart paste:
  - Windows: smart `Ctrl+V` clipboard paste:
    - text pastes normally,
    - image clipboard forwards to image-aware apps when text paste does not apply.
  - Windows plain-paste fallback: `Ctrl+Shift+V`.
  - `Shift+Insert` compatibility paste.
  - Linux/macOS: plain `Ctrl+Shift+V` clipboard paste.
- Paste undo/redo:
  - `Ctrl+Z` undo recent paste.
  - `Ctrl+Shift+Z` redo (best effort).
- Fast visual tuning:
  - `Ctrl+Alt+T` cycle color themes.
  - `Ctrl+Alt+F` cycle fonts.
  - Theme randomization uses a shuffle bag over a curated 86-theme pool:
    - pure black backgrounds only,
    - exact duplicate palettes removed,
    - near-similar palettes reduced (brighter options preferred),
    - low-variety/plain palettes removed.
- Borderless “black glass” mode:
  - `Ctrl+Alt+B` toggle title bar.
  - `Ctrl+Alt+D` drag window when borderless.
- Notification workflow boost:
  - Windows toast click now focuses the exact terminal pane/tab/window that raised it.
- Resize stability tuning:
  - Windows defaults to `WebGpu` renderer for smoother live window reshaping.
  - Override renderer with env var: `BENJAMINTERM_FRONT_END=OpenGL|WebGpu|Software`.
- Custom brand icon:
  - New square blood-red `BEN` icon applied to app/runtime/installer branding.
- Side-by-side install support:
  - BenjaminTerm now uses its own Windows app identity and executable names, so it can coexist with WezTerm and be pinned separately in the taskbar.

Full config docs: `extras/vibe/README.md`

## Hotkeys

| Action | Hotkey |
|---|---|
| Smart copy / pass-through interrupt | `Ctrl+C` |
| Force pass-through interrupt | `Ctrl+Alt+C` |
| Smart paste (Windows) | `Ctrl+V` |
| Plain paste fallback (Windows) | `Ctrl+Shift+V` |
| Paste (Windows compatibility) | `Shift+Insert` |
| Paste (Linux/macOS) | `Ctrl+Shift+V` |
| Plain paste (Linux/macOS) | `Alt+V` |
| Paste undo | `Ctrl+Z` |
| Paste redo | `Ctrl+Shift+Z` |
| Reload config | `Ctrl+Shift+R` |
| Search | `Ctrl+F` |
| Font size down/up/reset | `Ctrl+-` / `Ctrl+=` / `Ctrl+0` |
| Cycle theme | `Ctrl+Alt+T` |
| Cycle font | `Ctrl+Alt+F` |
| Toggle borderless | `Ctrl+Alt+B` |
| Start window drag | `Ctrl+Alt+D` |

## Install

### Windows (Primary)

- Use this fork's Windows installer or portable zip release.
- The distro bundles the vibe config next to the executable as `wezterm.lua`.
- Per-user override still wins:
  - `%USERPROFILE%\\.wezterm.lua`
  - `~/.config/wezterm/wezterm.lua`

### Linux (Friend Mode)

- Bootstrap docs: `extras/vibe/linux/README.md`
- Quick run:
  - `cd extras/vibe/linux`
  - `./bootstrap-popos.sh`
  - `benjaminterm`

## Build + Release Prep

- Release checklist: `RELEASING_BENJAMINTERM.md`
- This covers:
  - local validation,
  - Windows packaging guidance,
  - Linux bootstrap distribution notes,
  - GitHub release prep sequence.

## Upstream Credit

BenjaminTerm is a custom distribution/fork built on top of WezTerm.

- Upstream project: https://github.com/wez/wezterm
- Upstream docs: https://wezterm.org/

## License and Notices

- Project license: `LICENSE.md` (MIT).
- Third-party notice index: `licenses/THIRD_PARTY_NOTICES.md`.
- ANGLE license text: `licenses/ANGLE.md`.
- Bundled font license files:
  - `assets/fonts/LICENSE_OFL.txt`
  - `assets/fonts/LICENSE_POWERLINE_EXTRA.txt`
- Windows component attribution notes:
  - `assets/windows/conhost/README.md`
  - `assets/windows/mesa/README.md`

<img src="assets/icon/BENJAMINTERM.jpg" alt="BENJAMINTERM" width="110" />

WezTerm is MIT licensed; see `LICENSE.md`.
