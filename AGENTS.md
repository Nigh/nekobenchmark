# NekoBenchmark project state

NekoBenchmark is a local Godot 4.x/GDScript reaction-time application. Godot
owns the fullscreen window, UI, input, 3D renderer, depth buffer, and export.
The bundled Maple Mono font is used directly as a Godot resource.

## Current behavior

- The application opens fullscreen at a project-selection menu. The menu column
  sits on the left; the right side shows a best-score overview card with four
  project medians and a radar shape. Radar axes use fixed per-mode windows
  (lower ms → outer). The fill appears only when all four projects have a best;
  otherwise the axes stay empty and a hint asks to complete all four.
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
- `OSU` is a 2D sequence test: five rounds, each with six numbered circular
  targets (radius 48 px). Targets form a path with identical adjacent spacing
  (360 px). Only consecutive triples must be non-overlapping; non-adjacent
  circles may share space. Only the next two numbered circles are visible at a
  time. Hits fade out immediately, and a meteor-style streak runs from the next
  circle's edge to the following circle's edge. The player must hit them in
  order 1–6. Left mouse and react keys only count when the cursor is on the next
  expected circle. Score is first valid hit to last hit. A miss or out-of-order
  hit invalidates the whole five-round set.
- `Sphere Aim` is a 3D clear-out test: five rounds. Each round arms when the
  player hits a fixed center green gate (same world-center placement as Sens Lab
  at z = -8). Hitting the gate starts a random 1–3 second wait, then six
  non-overlapping spheres appear at once. Spawns keep at least one target in
  each view quadrant (top-left, top-right, bottom-left, bottom-right), stay
  inside about a 60° view cone, and stay inside the practice room. Visual sphere
  radius is 0.42 (1.2× the prior size). The player aims with limited mouse look
  and fires with left mouse or react keys using a center raycast against each
  sphere with a 1.1× visual-radius hit tolerance; hit spheres disappear
  immediately. Score is appear-frame to last hit. Early fire during the wait, or
  failing to clear all targets within six seconds, invalidates the whole set.
  Fires closer than 150 ms apart are ignored. Misses on the gate do not
  invalidate. After a successful clear, the next round's green gate appears
  immediately (no ready click).
- All 3D cameras use a shared Overwatch-style config: horizontal FOV 103° with
  `Camera3D.KEEP_WIDTH` (~70.5° vertical at 16:9). Shared 3D look sensitivity
  is a multiplier (default 1.00 → 0.006 rad/pixel), clamped to `[0.10, 5.00]`,
  adjusted in steps of 0.05 (wheel / nudge) or 0.01 when dragging the Sens Lab
  slider, and persisted as `look_sens` in `user://scores.txt`.
- All 3D modes share a bounded Overwatch-style practice room (floor underfoot,
  walls, ceiling) with a low-contrast line grid that fades with distance.
- Menu entry `3D Look Sensitivity` opens an unscored practice lab: four spheres
  (radius 0.42, same as Sphere Aim) in a square; clearing them spawns a green
  center gate sphere; hitting the gate respawns the four. Sensitivity value and
  slider stay at the bottom. The slider panel background stays mostly
  transparent while looking; holding Alt or adjusting sensitivity (wheel /
  slider) reveals it, then it fades again after 2 seconds idle or when Alt is
  released. Mouse wheel adjusts sensitivity; `-` / `=` adjust square spacing (no
  overlap, stay within a 90° view cone; the square rises so balls stay above the
  floor). Holding Alt shows the cursor so the slider can be dragged; releasing
  Alt recaptures look.
- Color Reaction and Corner Watch use a random 1–4 second delay, five trials, a
  one-second timeout, and false-start invalidation. Each valid non-final trial
  immediately begins its next random delay. `Time.get_ticks_usec()` measures
  engine-side timing; it is not a physical photon-time measurement.
- All project views and the summary show a left-side five-round result list.
  During an active timed trial a separate LIVE row shows elapsed ms and hides
  when the trial ends. Each valid result appears at screen center before easing
  into its list row over 0.5 seconds.
- Mouse input is not accumulated and VSync is disabled to minimize software
  input-to-frame latency; tearing is an accepted trade-off.
- The best completed median for each project is atomically saved as
  `user://scores.txt`, using the `color`, `shooter`, `osu`, `spheres`, and
  `look_sens` keys.
- Run `godot --headless --path . --script tests/reaction_state_test.gd`,
  `godot --headless --path . --script tests/sequence_state_test.gd`,
  `godot --headless --path . --script tests/playthrough_test.gd`, and
  `godot --headless --path . --editor --quit` to verify changes. Use the
  project export presets for release packages.

## Maintenance rule

When changing project behavior, controls, architecture, dependencies, build
commands, tests, or the persisted score format, update this file in the same
change so this project state remains accurate.
