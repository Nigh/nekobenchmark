# NekoBenchmark project state

NekoBenchmark is a local Godot 4.x/GDScript reaction-time application. Godot
owns the fullscreen window, UI, input, 3D renderer, depth buffer, and export.
The bundled Maple Mono font is used directly as a Godot resource.

## Current behavior

- The application opens fullscreen at a five-test menu. Tests are prominent pink
  buttons on the left; History and Settings live in a separate Tools section.
  The right side shows each project's best score, unit and direction, plus the
  latest 20 manually saved results as separate sparklines. There is no radar
  or combined score; fewer than two records show an empty trend hint.
- The native Godot UI uses the xianii dark palette from Nigh/xianii-theme
  (MIT; attribution in assets/licenses/xianii-theme-LICENSE.txt, included by
  all export presets), converted from
  OKLCH to sRGB. Maple Mono stays the only bundled font.
- The UI is English-only. Do not add CJK fonts or localized UI strings without
  explicitly revisiting the release-size requirement.
- `2D Reaction` measures five color-change trials. Space, Z, X, arrow keys,
  and left mouse button can respond.
- `3D Reaction` is a fixed low-poly Godot 3D scene. Mouse yaw spans 180°
  (`[-π/2, π/2]`) and pitch is unrestricted. A click is valid whenever the
  target is inside the camera frustum; each target starts from a random left or
  right cover, crosses to the other cover over its one-second response window,
  then times out. After a target round ends, it greys, falls, and fades before
  it is removed.
- `OSU` is a 2D sequence test: five rounds. Each round arms when the player
  hits a fixed center green gate (play-area center). Hitting the gate starts a
  random 1–3 second wait, then six numbered circular targets appear (radius
  48 px). Targets form a path with identical adjacent spacing (360 px); the
  first circle is also exactly one spacing from the green gate. Only consecutive
  triples must be non-overlapping; non-adjacent circles may share space. Only
  the next two numbered circles are visible at a time. Hits fade out
  immediately, and a meteor-style streak runs from the next circle's edge to
  the following circle's edge. The player must hit them in order 1–6. Left mouse
  and react keys only count when the cursor is on the next expected circle (or
  the green gate while arming). Score is first valid hit to last hit. An early
  click during the wait, a miss, or an out-of-order hit invalidates the whole
  five-round set. Misses on the gate do not invalidate. After a successful
  round, the next round's green gate appears immediately (no ready click).
- `3D Aim` is a 3D clear-out test: five rounds. Each round arms when the
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
- `3D Tracking` measures five 10-second rounds, each preceded by 3 seconds of
  stationary pre-aim. React keys or left click begin the set; thereafter only
  mouse look is needed. A radius-0.42 sphere moves on the world z=-8 plane
  around camera-start height. Horizontal/vertical angles are 22/6 degrees
  times sine waves: x frequencies [0.12, 0.15, 0.18, 0.16, 0.20] Hz and y
  frequencies [0.18, 0.12, 0.14, 0.23, 0.17] Hz, in a fixed repeatable order.
  Coverage uses the actual sphere radius without extra hit tolerance, weighted
  by monotonic elapsed time between rendered samples. Main score is median
  coverage percentage (higher is better); mean angular error is also shown.
  Losing focus cancels the set; misses reduce coverage but do not invalidate.
  LIVE shows remaining seconds and coverage; round results retain the flight
  animation. This complements reaction/click tests with sustained control.
- All 3D cameras use a shared config tuned for comfortable, responsive look:
  horizontal FOV 103° with `Camera3D.KEEP_WIDTH` (~70.5° vertical at 16:9).
  Shared 3D look sensitivity is a multiplier (default 1.00 → 0.006 rad/pixel),
  clamped to `[0.10, 5.00]`, adjusted in steps of 0.05 (wheel / nudge) or 0.01
  when dragging the Sens Lab slider, and persisted as `look_sens` in
  `user://scores.txt`.
- All 3D modes share a bounded practice room (floor underfoot, walls, ceiling)
  with a low-contrast line grid that fades with distance.
- Settings contains a persisted shared sensitivity slider and `Open Sens Lab`,
  which opens an unscored practice lab: four spheres
  (radius 0.42, same as 3D Aim) in a square; clearing them spawns a green
  center gate sphere; hitting the gate respawns the four. Sensitivity value and
  slider stay at the bottom. The slider panel background stays mostly
  transparent while looking; holding Alt or adjusting sensitivity (wheel /
  slider) reveals it, then it fades again after 2 seconds idle or when Alt is
  released. Mouse wheel adjusts sensitivity; `-` / `=` adjust square spacing (no
  overlap, stay within a 90° view cone; the square rises so balls stay above the
  floor). Holding Alt shows the cursor so the slider can be dragged; releasing
  Alt recaptures look.
- Scores measure the combined human + computer response chain, not isolated
  human RT or hardware latency. Meaningful comparisons keep one side fixed:
  different people on the same PC; the same person across PCs (device impact);
  or the same person on the same PC over time (form). Comparing different
  people on different PCs is not very meaningful.
- 2D Reaction and 3D Reaction use a random 1–4 second delay, five trials, a
  one-second timeout, and false-start invalidation. Each valid non-final trial
  immediately begins its next random delay. `Time.get_ticks_usec()` measures
  engine-side timing; it is not a physical photon-time measurement.
- All project views and the summary show a left-side five-round result list.
  During an active time-based trial a separate LIVE row shows elapsed ms and hides
  when the trial ends. Each valid result appears at screen center before easing
  into its list row over 0.5 seconds.
- Mouse input is not accumulated and VSync is disabled to minimize software
  input-to-frame latency; tearing is an accepted trade-off.
- The best completed median for each project is atomically saved as
  `user://scores.txt`, using the existing `color`, `shooter`, `osu`, `spheres`,
  and `look_sens` keys plus `tracking` (higher coverage wins; missing is -1 in
  memory, an actual 0% is valid). Old files load without migration. Failed
  writes roll back the changed in-memory best or sensitivity.
- Completed results freeze five samples, statistics, sensitivity, UTC timestamp,
  local completion time and UTC offset before the last score animation ends.
  Best scores update automatically; History is opt-in via `Save Result` on the
  result page. An optional 64-character tag supports device/setup/form labels.
  Successful saves disable the button; failures retain the result for retry.
  Result pages release the mouse and stop look input; typing in Tag consumes
  retry hotkeys. Retry re-enters the test and restores its mouse mode.
- History is an atomically replaced `user://history.json`, format version 1.
  Each record has id, project, rule_version, timestamp_utc, local_time,
  utc_offset_minutes, samples (microseconds for time tests; percentages for
  tracking), stats (median/mean/sample standard deviation in display units),
  look_sens, tag and errors_degrees (five for tracking, empty otherwise).
  Invalid, unreadable or unsupported files are protected from overwrite.
  Existing best scores are not converted into historical attempts.
- History supports project/tag/rule-version filtering, newest-first lists of
  50 records per page, and a chronological chart of the latest 100 filtered
  records. Clicking a row or point reveals all rounds and metadata. Different
  rule versions never share a trend. Empty/single/constant-value trends work.
  Cloud sync, export, editing and deletion are not included.
- Run `godot --headless --path . --script tests/reaction_state_test.gd`,
  `godot --headless --path . --script tests/sequence_state_test.gd`,
  `godot --headless --path . --script tests/playthrough_test.gd`,
  `godot --headless --path . --script tests/history_tracking_test.gd`, and
  `godot --headless --path . --editor --quit` to verify changes. Use the
  project export presets for release packages. Persistence checks use isolated
  test files, never real score/history files. The release workflow runs the
  same import and four checks, and packages the xianii MIT notice alongside
  the font license.

## Maintenance rule

When changing project behavior, controls, architecture, dependencies, build
commands, tests, or the persisted score format, update this file in the same
change so this project state remains accurate.
