# Status Item Icon

This folder stores design-source files for the custom Swooshy menu bar icon.

Suggested workflow:

- Start from `source.png` or a vector design file from Figma, Sketch, Recraft, or Inkscape.
- Keep the final icon monochrome and suitable for macOS template-image rendering.
- Keep the composition readable at `18x18` points and `36x36` pixels.
- Prefer a single-color icon on a transparent background.
- Focus on the wind `S` and a minimal window hint instead of the full app icon artwork.

Build the runtime resource with:

- `./scripts/build-status-item-icon.sh`

This generates:

- `Sources/Swooshy/Resources/StatusItem/SwooshyStatusTemplate.png`
- `Sources/Swooshy/Resources/StatusItem/SwooshyStatusTemplate.pdf`

Suggested source files:

- `source.png`
- `swooshy-status-item.fig`
- `swooshy-status-item.svg`
- `swooshy-status-item.pdf`
