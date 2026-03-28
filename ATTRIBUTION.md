# Attribution and Upstream Notes

This repository is released under the GNU General Public License v3.0.

At the time of writing, the code in this repository does not vendor or copy
source files from third-party projects. The projects below are tracked as
research references, architectural inspiration, or future integration
candidates and should be re-reviewed before any source code is copied or
bundled.

## Reference Projects

- Rectangle: https://github.com/rxhanson/Rectangle
- Swindler: https://github.com/tmandry/Swindler
- Phoenix: https://github.com/kasper/phoenix
- Hammerspoon: https://github.com/Hammerspoon/hammerspoon
- yabai: https://github.com/koekeishiya/yabai
- OpenMultitouchSupport: https://github.com/Kyome22/OpenMultitouchSupport

## Rules for Future Imports

- Any copied or vendored code must retain upstream copyright notices.
- Any new dependency must be checked for GPL compatibility before import.
- Project notes should distinguish between "inspiration/reference" and
  "embedded code" so the repository history stays clean.
- Private framework experiments should be isolated behind a clearly labeled
  module and documented separately from the core window engine.
