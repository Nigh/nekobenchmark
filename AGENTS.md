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
- `OSU` is a 2D sequence test: five rounds, each with six non-overlapping
  numbered circles placed at random. The player must hit them in order 1–6.
  Mouse clicks must land on the next expected circle; Space, Z, X, and arrow
  keys advance the next expected circle. Score is first valid hit to last hit.
  A wrong click (miss or out of order) invalidates the whole five-round set.
- `Sphere Aim` is a 3D clear-out test: five rounds. After a random 1–3 second
  wait, six spheres appear at once. The player aims with limited mouse look and
  fires with left mouse using a center raycast. Score is appear-frame to last
  hit. Early fire, or failing to clear all targets within six seconds,
  invalidates the whole set. Fires closer than 150 ms apart are ignored.
- Color Reaction and Corner Watch use a random 1–4 second delay, five trials, a
  one-second timeout, and false-start invalidation. Each valid non-final trial
  immediately begins its next random delay. `Time.get_ticks_usec()` measures
  engine-side timing; it is not a physical photon-time measurement.
- All project views and the summary show a left-side five-round result list.
  Each valid result appears at screen center before easing into its list row
  over 0.5 seconds.
- Mouse input is not accumulated and VSync is disabled to minimize software
  input-to-frame latency; tearing is an accepted trade-off.
- The best completed median for each project is atomically saved as
  `user://scores.txt`, using the `color`, `shooter`, `osu`, and `spheres` keys.
- Run `godot --headless --path . --script tests/reaction_state_test.gd`,
  `godot --headless --path . --script tests/sequence_state_test.gd`, and
  `godot --headless --path . --editor --quit` to verify changes. Use the
  project export presets for release packages.

## Maintenance rule

When changing project behavior, controls, architecture, dependencies, build
commands, tests, or the persisted score format, update this file in the same
change so this project state remains accurate.
