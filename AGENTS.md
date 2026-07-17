# NekoBenchmark project state

NekoBenchmark is a local Godot 4.x/GDScript reaction-time application. Godot
owns the fullscreen window, UI, input, 3D renderer, depth buffer, and export.
The bundled Maple Mono font is used directly as a Godot resource.

## Current behavior

- The application opens fullscreen at a project-selection menu.
- The UI is English-only. Do not add CJK fonts or localized UI strings without
  explicitly revisiting the release-size requirement.
- `Color Reaction` measures five color-change trials. Space, Z, X, arrow keys,
  and left mouse button can respond.
- `Corner Watch` is a fixed low-poly Godot 3D scene. Mouse yaw spans 180°
  (`[-π/2, π/2]`) and pitch is unrestricted. A click is valid whenever the
  target is inside the camera frustum; each target starts from a random left or
  right cover, crosses to the other cover over its one-second response window,
  then times out. After a target round ends, it greys, falls, and fades before
  it is removed.
- Both projects use a random 1–4 second delay, five trials, a one-second
  timeout, and false-start invalidation. Each valid non-final trial immediately
  begins its next random delay. `Time.get_ticks_usec()` measures engine-side
  target-frame to input timing; it is not a physical photon-time measurement.
- Both project views and the summary show a left-side five-round result list.
  Each valid result appears at screen center before easing into its list row
  over 0.5 seconds.
- Mouse input is not accumulated and VSync is disabled to minimize software
  input-to-frame latency; tearing is an accepted trade-off.
- The best completed median for each project is atomically saved as
  `user://scores.txt`, using the `color` and `shooter` keys.
- Run `godot --headless --path . --script tests/reaction_state_test.gd` and
  `godot --headless --path . --editor --quit` to verify changes. Use the
  project export presets for release packages.

## Maintenance rule

When changing project behavior, controls, architecture, dependencies, build
commands, tests, or the persisted score format, update this file in the same
change so this project state remains accurate.
