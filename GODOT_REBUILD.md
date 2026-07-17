# NekoBenchmark Godot rebuild guide

This document specifies a clean Godot implementation of NekoBenchmark. It is
intended to replace the current SDL/C++ application; do not try to embed Godot
inside the existing executable or keep two renderers in one window.

## Goal and non-goals

Build one local, fullscreen, English-only desktop application with two
reaction-time projects:

1. **Color Reaction**: five rounds of a color change.
2. **Corner Watch**: five rounds in a fixed, low-poly 3D scene. A target
   slides out from a corner, then the player shoots it.

Godot owns the window, input, 2D UI, 3D renderer, depth buffer, and
presentation. The application must not depend on SDL, CMake, SDL_ttf, custom
SPIR-V shaders, or the current C++ renderer.

This application measures software event-to-target-frame timing. It can make
the target state and its recorded start time occur in the same engine frame,
but no consumer OS/game engine can guarantee physical photon timing within one
display refresh without external hardware calibration.

## Functional requirements

### Shared trial rules

- Start at a fullscreen project-selection menu.
- English UI only.
- Random wait before a target: uniform 1–4 seconds.
- Five valid trials per project.
- One-second response timeout.
- A response before the target invalidates the round and clears partial
  results.
- Show median, mean, and sample standard deviation after five valid trials.
- Persist the best completed median per project in `user://scores.txt`.
- Preserve the existing text format:

  ```text
  color 182.4
  shooter 211.8
  ```

- The `R` key restarts after a summary. `Esc` returns to the menu (or exits
  from the menu).

### Color Reaction

- Ready state: explain the control.
- Waiting state: red background and no valid response.
- Target state: green background and “NOW”.
- Accepted controls: Space, Z, X, arrow keys, or left mouse button.
- After a valid trial, require another input to begin the next wait.

### Corner Watch

- Use a normal Godot 3D scene with `Camera3D`, `WorldEnvironment`,
  `DirectionalLight3D`, floor/wall meshes, and a target mesh.
- Clamp yaw to `[-π/2, π/2]` radians, a 180° horizontal arc. Do not clamp
  pitch.
- Horizontal look must match normal first-person convention: mouse motion to
  the right turns the view right.
- The target appears at a random left or right cover on its first target frame,
  then crosses to the opposite cover over the one-second response window.
- Start measurement when the target is first made visible for rendering, not
  when the random wait deadline is reached.
- A left click is valid whenever the target is inside the camera frustum. A
  click during waiting, while the target is outside the view, or after timeout
  invalidates the round.
- Draw the crosshair, progress dots, instructions, and result overlay with
  `Control` nodes above the 3D viewport.

## Required installation

Install these before the implementation chat:

| Item | Required version / purpose |
| --- | --- |
| Godot editor | Godot 4.4 stable or a later Godot 4.x stable release; standard GDScript build is sufficient |
| Godot export templates | Same version as the editor |
| Vulkan-capable graphics driver | Required for the Forward+ renderer on Linux/Windows; use Godot Compatibility renderer only as a tested fallback |
| Git | Source control |
| Optional: Blender | Only if replacing the procedural low-poly meshes with authored models |

No Godot Asset Library packages are required. Do not add GUT or another test
framework for this project; use a small headless GDScript assertion runner.

On Linux, install the editor from Godot's official download or a trusted
distribution package, then verify:

```sh
godot --version
godot --headless --path . --editor --quit
```

The executable may be named `godot4` instead of `godot`.

## New project layout

Create a new Godot project at the repository root. Remove the SDL build and
source tree only after the Godot version is usable and feature-equivalent.

```text
project.godot
assets/
  MapleMono-Regular.ttf
scenes/
  Main.tscn
  corner_watch.tscn
scripts/
  app.gd
  reaction_state.gd
  score_store.gd
  corner_watch.gd
tests/
  reaction_state_test.gd
```

`Main.tscn` should contain:

```text
Main (Node)
├── Menu (Control)
├── ColorReaction (Control)
├── CornerWatch (Node3D, instanced scene)
├── Summary (Control)
└── CanvasLayer
    └── HUD (Control)
```

Only one project view is visible at a time. Keep all user-facing text in
GDScript constants or scene labels; do not add localized strings or CJK fonts.

## State model

Implement the shared state machine in `scripts/reaction_state.gd`. Keep it
independent from Godot nodes so it can run in headless tests.

```text
READY
  └── input → WAITING
WAITING
  ├── early input → INVALID
  └── deadline → TARGET
TARGET
  ├── valid response → WAITING or SUMMARY
  └── one-second timeout → INVALID
INVALID
  └── input → WAITING
SUMMARY
  └── R → READY
```

Suggested state fields:

```gdscript
var stage: Stage = Stage.READY
var deadline_us := 0
var target_frame_us := 0
var reactions_us: Array[int] = []
const WAIT_MIN_US := 1_000_000
const WAIT_MAX_US := 4_000_000
const TIMEOUT_US := 1_000_000
```

Use `Time.get_ticks_usec()` consistently for both target-frame and input
handling timestamps. Godot's input events do not provide a portable hardware
event timestamp equivalent to all SDL backends, so document results as
engine-side measurements.

When the waiting deadline is reached in `_process`:

1. Set `target_frame_us = Time.get_ticks_usec()`.
2. Change to `TARGET`.
3. Apply the visual target state immediately: green color or target visibility.
4. Do not allocate fonts, instantiate meshes, load resources, compile shaders,
   or write files on this transition.

The resulting target timestamp represents the first engine frame that contains
the target. It is deliberately not claimed to be an exact physical scanout
timestamp.

## Detailed implementation sequence

### 1. Create and configure the Godot project

1. Create `project.godot` using the Godot editor.
2. Set display stretch mode to `canvas_items` and enable a 1280×720 reference
   UI layout.
3. On startup, request fullscreen with:

   ```gdscript
   DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
   ```

4. Set up Input Map actions:
   - `react`: Space, Z, X, all four arrows, left mouse button.
   - `restart`: R.
   - `back`: Escape.
   - `fire`: left mouse button.
5. Add `assets/MapleMono-Regular.ttf`, create a `FontFile` resource from it,
   and assign it to the shared `Theme`.

### 2. Implement persistence and statistics

Create `score_store.gd`.

- Parse only non-negative numeric values after the keys `color` and `shooter`.
- Calculate median from a sorted five-value copy.
- Calculate mean and sample standard deviation using divisor `n - 1`.
- When a new best is complete, write `user://scores.txt.tmp`, then rename it
  to `user://scores.txt` with `DirAccess.rename_absolute`. Retain the previous
  file if writing fails.

### 3. Implement Color Reaction first

1. Create the full-screen `ColorReaction` `Control`.
2. Add title, instruction, progress dots, and footer with Labels/ColorRects.
3. Drive its background and text from `reaction_state.gd`.
4. In `_unhandled_input`, pass the current `Time.get_ticks_usec()` and whether
   the event is a `react` action into the shared state machine.
5. Preload all labels and apply the theme during `_ready`, before any trial.
6. Add the summary overlay and persistence update.

Verify false starts, timeout, five-trial result, restart, and best-score
persistence before creating any 3D content.

### 4. Build the Corner Watch scene

1. Create `corner_watch.tscn` rooted at `Node3D`.
2. Add:
   - `WorldEnvironment` with a neutral dark environment.
   - `DirectionalLight3D` and optional low-intensity fill light.
   - `Camera3D` at the fixed origin.
   - Floor and cover objects as `MeshInstance3D` nodes using
     `BoxMesh`/`PlaneMesh` and `StandardMaterial3D`.
   - `Enemy` as a `Node3D` containing a low-poly `MeshInstance3D`.
3. Precreate the enemy and keep it hidden/off-corner during waiting; never
   instantiate it at target time.
4. Capture the mouse only while this project is active:

   ```gdscript
   Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
   ```

5. In `_input(event)`, apply `event.relative` to yaw and pitch. Clamp only yaw
   before assigning camera rotation.
6. For a fire event during `TARGET`, accept the response when
   `camera.is_position_in_frustum(enemy.global_position)` is true.
7. At target transition, set `enemy.visible = true`, set its initial offset,
   and save `target_frame_us`.
8. At target transition, select a random source cover and make the target
   visible. In `_process`, interpolate only its transform over `TIMEOUT_US`:

   ```gdscript
   var p := minf(1.0, float(now_us - target_frame_us) / TIMEOUT_US)
   enemy.position.x = lerpf(source_x, destination_x, p)
   ```

9. Add `CanvasLayer/HUD` with a center crosshair, trial dots, instructions,
   invalid message, and summary. These are normal Godot `Control` nodes, so
   their draw order is reliably above the 3D scene.

### 5. Integrate navigation

`app.gd` owns page switching, score loading, and Escape behavior.

- On page entry, reset the shared state and hide all other pages.
- Corner Watch entry captures the pointer; every other page makes it visible.
- Disable or clear enemy visibility before returning to the menu.
- Use one random number generator instance seeded once during startup.

### 6. Add headless tests

Create `tests/reaction_state_test.gd` with assertions for:

- Early response invalidates and clears samples.
- Target response stores `input_us - target_frame_us`.
- Timeout invalidates and clears samples.
- Fifth valid sample enters `SUMMARY`.
- Target travel progress is `0.0` at target start and `1.0` after one second.
- Median and best-score update behavior.

Run it without a test dependency:

```sh
godot --headless --path . --script tests/reaction_state_test.gd
```

## Verification checklist

- Export and run a fullscreen build on each target platform.
- Confirm only one Godot renderer owns the window and no frame alternation or
  flickering occurs.
- Verify 3D occlusion by moving the Corner Watch camera within each clamp.
- Verify rightward mouse motion turns the view right.
- Confirm target visibility on the first target frame and arrival at the
  opposite cover at the one-second timeout.
- Confirm the target state contains no allocation/resource loading in profiling.
- Confirm Color Reaction and Corner Watch each save independent best medians.
- Check `user://scores.txt` survives application restart.
- Record engine version, display refresh rate, VSync mode, GPU driver, and
  operating system alongside benchmark results.

## Export notes

Use Godot export presets for Linux, Windows, and macOS. Include the project
font and scenes as normal project resources. Do not copy shaders manually:
Godot imports and packages them with the project. Use the Forward+ renderer
where Vulkan/Metal support is available; test Compatibility separately if it
is needed for older hardware.

## Handoff prompt for the next implementation chat

Use this prompt in the new conversation:

> Rebuild this repository as the Godot project specified in
> `GODOT_REBUILD.md`. Godot 4.x and export templates are installed. Replace
> the SDL/CMake application rather than mixing engines. Implement and verify
> all functional requirements, the headless state-machine tests, and the
> fullscreen Linux export first. Preserve the English-only UI and the
> `user://scores.txt` score format.
