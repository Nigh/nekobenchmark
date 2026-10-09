# NekoBenchmark project state

NekoBenchmark is a local Godot 4.x/GDScript reaction-time application. Godot
owns the fullscreen window, UI, input, 3D renderer, depth buffer, and export.
The bundled Maple Mono font is used directly as a Godot resource.

## Current behavior

- The application opens fullscreen at a five-test menu. Tests are prominent project-colored
  buttons on the left; History and Settings live in a separate Tools section.
  The right side shows each project's latest valid result from this app run,
  a five-axis 0–100 radar, its raw score and save-window countdown. Saving does
  not clear the display. Results at least one hour old remain visible with faded
  rows/titles and radar labels/markers, marked EXPIRED, and cannot be saved.
  Missing radar axes show -- and are unfilled. Result-page radars use the current
  result and the latest cached results, including expired display snapshots.
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
  then times out. A warm ceiling spotlight softly illuminates the three covers
  and target crossing area. After a target round ends, it greys, falls, and fades before
  it is removed.
- `OSU` is a 2D sequence test: five rounds. Each round arms when the player
  hits a fixed center green gate (play-area center). Hitting the gate starts a
  random 1–3 second wait, then six numbered circular targets appear (radius
  48 px). Targets form a path with identical adjacent spacing (360 px); the
  first circle is also exactly one spacing from the green gate. Only consecutive
  triples must be non-overlapping; non-adjacent circles may share space. Only
  the next three numbered circles are visible at a time, at opacity 1.0/0.6/0.3.
  The current target appears immediately; the next two begin 200ms fades after
  200/400ms delays. After each hit, subsequent target opacity transitions take
  200ms with no delay, starting from their current alpha. Hit/reveal tweens bind
  to their circle nodes and are canceled when nodes are freed; no lambda captures
  freed target nodes. Hits fade out
  immediately, and a meteor-style streak runs from the next circle's edge to
  the following circle's edge. The player must hit them in order 1–6. Left mouse
  and react keys only count when the cursor is on the next expected circle (or
  the green gate while arming). Score is first valid hit to last hit, with a six-second timeout starting at
  the first hit. An early
  click during the wait, a miss, or an out-of-order hit invalidates the whole
  five-round set. Misses on the gate do not invalidate. After a successful
  round, the next round's green gate appears immediately (no ready click).
- `3D Aim` is a 3D clear-out test: five rounds. Each round arms when the
  player hits a fixed center green gate (same default world-center placement as Sens Lab
  at z = -8). Hitting the gate starts a random 1–3 second wait, then six
  non-overlapping spheres appear at once. Five fixed world-space target layouts
  appear once each per set in shuffled order, independent of the camera look.
  Layouts keep at least one target in
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
- `3D Tracking` measures five 10-second scored rounds and starts preparation
  automatically on entry; only mouse look is needed. Each round moves immediately
  and starts scoring after the crosshair stays in the outer circle continuously
  for one second; leaving it resets acquisition. Scoring does not restart movement. Preparation caps angular speed at 20 degrees
  per second through conservative phase scaling; over the first scored second
  the phase-speed multiplier ramps linearly back to full speed. Muted target
  colors distinguish preparation; an outer-edge ring fills during acquisition,
  resets on loss, and a distinct two-note start tone signals scoring start. Growing acquisition
  progress plays the existing slide cue with its 40ms throttle; resets are silent.
  The camera-facing concentric circles have outer/inner radii 0.42/0.21 on the
  world z=-8 plane around camera-start height. Inner hits score 1, outer-ring hits
  0.5, outside hits 0, weighted by monotonic elapsed time between rendered samples.
  Horizontal/vertical angles are 22/6 degrees times sine waves: x frequencies
  [0.5, 0.6, 0.7, 0.6, 0.8] Hz and y [0.7, 0.5, 0.6, 0.9, 0.7] Hz. Every path
  loops smoothly over 10 seconds, with phase t + 0.55/(TAU*0.2)*sin(TAU*0.2*t),
  giving smooth speed modulation from 0.45× to 1.55×. The five fixed paths
  appear once each per set in shuffled order, including after focus recovery.
  The inner high-score circle is yellow. During scoring, inner/outer coverage
  plays a continuous quiet 880/440 Hz tone respectively. This coverage tone is
  silent outside, during preparation, on focus loss, at round completion and
  when leaving the test; existing discrete cues remain.
  Main score is median weighted score percentage (higher is better);
  mean angular error is also shown. Tracking uses rule_version 4, 3D Aim uses 2, OSU uses 3, and other tests use 1.
  Losing focus cancels the set; regaining focus automatically starts a fresh set. Misses reduce coverage but do not invalidate.
  LIVE shows remaining seconds and score; round results retain the flight
  animation. This complements reaction/click tests with sustained control.
- All 3D cameras use a shared config tuned for comfortable, responsive look:
  horizontal FOV 103° with `Camera3D.KEEP_WIDTH` (~70.5° vertical at 16:9).
  Shared 3D look sensitivity is a multiplier (default 1.00 → 0.006 rad/pixel),
  clamped to `[0.10, 5.00]`, adjusted in steps of 0.05 (wheel / nudge) or 0.01
  when Alt is held in Sens Lab or when dragging a slider, persisted as `look_sens` in
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
  floor). `[` / `]` bring targets and gate closer/further in steps of 0.25,
  distance clamped to [3, 20], default 8. Spacing shrinks if needed at closer
  distances. Both spacing and distance keys accept OS key repeats for long presses.
  Full square side (default 3) and distance are persisted as `lab_spacing` and
  `lab_distance`; failed saves restore both the settings and scene layout.
  Holding Alt shows the cursor so the slider can be dragged; releasing Alt recaptures look.
- Every score display uses logarithmic 0–100 points to one decimal, retaining
  raw ms/weighted coverage. Project points convert the five-round raw median;
  cache ordering still uses unrounded raw values. History retains raw snapshots
  and derives points on display, with no file-format change. Reaction anchors
  are 50ms=100, 220ms=80, 1000ms=0; OSU anchors 500ms=100, 1800ms=70,
  6000ms=0; interpolate linearly in log(time) between anchors, clamped 0–100.
  Aim uses clamp(60*ln(6000/t)/ln(6000/2400), 0, 100), so 2400ms=60.
  Tracking uses 60*ln(1+c)/ln(31) up to 30% coverage, then
  60+40*ln(c/30)/ln(100/30), giving 0%=0, 30%=60, 100%=100.
  Invalid/timeout sets show 0.0 points and cannot enter the result cache.
  History charts use points, higher is better; complete rule-version combinations
  remain separate. A single project-to-color mapping uses pink/purple/teal/yellow/
  green for 2D Reaction/3D Reaction/OSU/3D Aim/Tracking across menu borders/text,
  score header badges, results, radar axes and history bars/legend. Score card
  titles have equal-width solid project-color backgrounds and dark bold text;
  FontVariation emboldens Maple Mono without an extra bundled font. Menu result
  rows separate prominent points, smaller raw scores and muted save countdowns.
  The menu shows total points out of 500 only when all five display snapshots
  exist; incomplete totals show -- with a result count. Expired totals fade and
  carry an EXPIRED label, while saved totals remain visible.
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
  Its decorative panel ignores mouse input, allowing clicks on overlapping OSU
  targets. Hit eligibility depends on order and position, never reveal opacity;
  the current target can be hit before its 200ms transition reaches full opacity.
  OSU mouse hits transform the click event's viewport coordinates into page
  coordinates. Keyboard reactions use the last mouse-event position recorded
  in `_input`, preserving event order even when the cursor moves off a target
  immediately after the key press within the same input batch. Entry seeds this
  position for a stationary cursor; keyboard echoes remain ignored.
  During an active time-based trial a separate LIVE row shows elapsed ms and hides
  when the trial ends. Each valid result appears at screen center before easing
  into its list row over 0.5 seconds.
- Mouse input is not accumulated and VSync is disabled to minimize software
  input-to-frame latency; tearing is an accepted trade-off.
- A shared native AudioStreamPlayer plays cached, generated PCM cues, with a
  separate looping player for continuous Tracking coverage feedback: successful
  responses/hits 22 ms, early input/misses/timeouts 35 ms, hover/press/slide
  10/15/8 ms. Entering WAIT from idle/arming plays a dedicated 90ms two-note
  start cue instead of the response/press cue; automatic reaction round waits
  also play this cue. Gameplay cues play after timing/state handling; react echoes, ignored
  cooldown inputs and Tag typing stay silent. UI controls share hover/press cues;
  changed slider values use a 40 ms sound throttle and programmatic sync is silent.
- `user://scores.txt` now persists settings only: `look_sens`, `lab_spacing`,
  `lab_distance` and `data_epoch 2`. Legacy best-score keys are accepted on load
  but ignored and omitted on the next settings write. No test result writes this file.
  On first load of valid pre-epoch-2 files, old bests/history are discarded with
  atomic replacements while sensitivity is preserved. Invalid/unreadable/unsupported
  files are protected; reset failure blocks writes until restart and appears on the menu.
  Failed settings writes restore the previous in-memory value and scene layout.
- Completed tests freeze five samples, statistics, sensitivity, UTC timestamp,
  local completion time and UTC offset before the final score animation ends.
  A ResultCache stores only the latest valid snapshot per project in memory,
  replacing it even when the new score is worse. One-hour save eligibility uses
  monotonic microseconds; expired and saved snapshots stay available for display
  until replaced or app exit. Valid 0% Tracking results are retained. The menu
  refreshes countdowns and expiry styling each second.
- Result pages have Retry/Menu only. `Save Session` and optional 64-character
  Tag exist only on the menu. All five projects must have unexpired, unsaved cached results;
  clicking Save rechecks expiry and atomically saves the five latest results as
  one session. Success marks those snapshots saved and clears the tag, without
  changing the displayed scores/radar. Already saved results cannot be saved again;
  all five projects need fresh results for another session. Failure retains the
  results for retry within their original save windows. Cache is never saved on
  exit or restored on startup. Result pages release the mouse and stop look;
  retry restores it.
- History is an atomically replaced `user://history.json`, format version 2,
  with data_epoch 2, sessions and legacy_records. Each session stores id, saved
  timestamp_utc/local_time/utc_offset_minutes, one tag, and exactly one complete
  result for each of the five projects. Each result retains its original completion
  time, five samples, stats, sensitivity, rule_version and Tracking angular errors.
  A derived flat index remains available for record lookup and validation;
  session timestamps order session lists/charts. Session details show all five
  saved results, while individual rounds/completion metadata live in bar tooltips. Valid epoch-2 format-v1 single results remain explicitly
  labeled legacy records and are preserved when new sessions are saved; they are
  never fabricated into complete sessions. Invalid or future formats cannot overwrite.
- History has no project, tag or rules-version filters. It shows all sessions
  and explicitly labeled legacy singles, with newest-first lists of 50 entries
  per page and chronological grouped bars for the latest 100 entries. List rows
  show local date/time, total points (sum of the five unrounded project scores,
  displayed to one decimal, out of 500), and tag. Legacy singles show their actual
  points out of 100, not a fabricated session total. Each session has all five
  project-colored bars on a fixed 0–100 y-axis. Bars are 18px wide with 3px internal
  gaps and larger group gaps; overflow supports horizontal wheel/pan/drag navigation
  and a position indicator. Hover highlights a bar with a border and shows a
  tooltip with that test's raw/point score, rounds, completion time/UTC offset,
  sensitivity, tag, rules version, statistics and Tracking angular error. Leaving
  or scrolling hides the tooltip. Clicking anywhere in a chart group or a list row
  selects the whole session; white vertical selection edges enclose centered bars
  and date labels (legacy single bars are also centered). Details separate a
  prominent session total, muted metadata/tag, project-colored test names and
  per-test points with secondary raw scores, rules versions and sensitivities,
  alongside a radar at the lower right. Rules versions appear only
  in those details and tooltips. Legacy singles have only their actual bar/radar
  axis. Empty/single/zero/constant-value charts work. Cloud sync, export, editing
  and deletion are not included.
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
