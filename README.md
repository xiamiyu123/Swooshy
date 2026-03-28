# Sweeesh

Sweeesh is an experimental open-source macOS window utility aimed at becoming
an open alternative to touchpad-first window tools. The first version focuses
on the reliable part of the stack: a menubar app that uses Accessibility APIs
to move and resize the focused window.

## Current MVP

- Menubar-only app with no Dock presence
- Accessibility permission prompt and refresh flow
- Built-in English and Simplified Chinese localization
- Global hotkeys for all core window actions
- Settings window for language override, hotkey enable/disable, and per-action shortcut recording
- Focused-window actions:
  - snap left half
  - snap right half
  - maximize to visible frame
  - center a large window
  - minimize the focused window to the Dock
  - close the focused window
  - quit the frontmost application
  - cycle through windows from the same application
- Pure geometry tests for layout behavior

## Why This Scope

The project is intentionally starting with the window engine before raw
trackpad gesture capture. Public macOS gesture APIs are app-local and system
gestures take precedence, so the riskiest input work is deferred until the
core behavior is stable and useful.

## Running the App

1. Open `Package.swift` in Xcode and run the `Sweeesh` executable target.
2. Or run `swift run` from the project root.
3. Grant Accessibility access when prompted.
4. Use the menu bar icon to trigger window actions.
5. Open `Settings…` from the menu bar menu to change language and customize shortcuts.

## Default Hotkeys

- `Control + Option + Command + Left Arrow`: snap left half
- `Control + Option + Command + Right Arrow`: snap right half
- `Control + Option + Command + Up Arrow`: maximize to visible frame
- `Control + Option + Command + C`: center large window
- `Control + Option + Command + M`: minimize to Dock
- `Control + Option + Command + W`: close the focused window
- `Control + Option + Command + Q`: quit the frontmost application
- `Control + Option + Command + \``: cycle same-app windows

## Project Structure

- `Sources/Sweeesh/SweeeshApp.swift`: App entry point
- `Sources/Sweeesh/AppDelegate.swift`: lifecycle bootstrap
- `Sources/Sweeesh/StatusBarController.swift`: menu bar UI and action wiring
- `Sources/Sweeesh/SettingsStore.swift`: persisted app settings
- `Sources/Sweeesh/SettingsWindowController.swift`: SwiftUI-backed settings window
- `Sources/Sweeesh/Localization.swift`: localized string lookup
- `Sources/Sweeesh/Resources/*.lproj`: language resources
- `Sources/Sweeesh/WindowManager.swift`: Accessibility-based focused-window IO
- `Sources/Sweeesh/WindowLayoutEngine.swift`: pure layout calculations
- `ATTRIBUTION.md`: tracked reference projects and license discipline

## Roadmap

- Expand settings with layout ratios and launch-at-login behavior
- Add a separate experimental module for raw trackpad input
- Explore private-framework experiments only after the public MVP is solid

## License

This project is licensed under the GNU General Public License v3.0.
See `LICENSE` for the full text and `ATTRIBUTION.md` for reference-project
tracking.
