## BenjaminTerm v2026.02.24

Windows-first BenjaminTerm release focused on workflow stability and visual quality.

### Included Artifact
- `BenjaminTerm-windows-v2026.02.24.zip`
- `BenjaminTerm-windows-v2026.02.24.zip.sha256`

### Highlights
- Clipboard reliability improvements:
  - Windows `Ctrl+V` uses smart paste:
    - text pastes immediately,
    - image clipboard content forwards to image-aware coding tools if text paste doesn't apply.
  - `Ctrl+Shift+V` remains guaranteed plain clipboard paste fallback.
  - `Shift+Insert` compatibility paste binding retained.
  - Restored compatibility with OpenWhispr transcription and Win+Shift+S screenshot-to-prompt workflows.
- Curated theme system overhaul:
  - Shuffle-bag rotation (no repeat until bag exhaustion).
  - Pure-black background filtering.
  - Exact duplicate palette dedupe.
  - Near-similar palette reduction with brighter preference.
  - Low-variety/plain palette filtering.
  - Resulting curated pool: `86` themes.
- Existing quality-of-life features retained:
  - smart `Ctrl+C`,
  - paste undo/redo,
  - theme/font cycling,
  - borderless workflow hotkeys.

### Integrity
Use the `.sha256` file to verify the zip checksum after download.
