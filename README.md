<h1 align="center">SyncRateBench</h1>

<p align="center">
  English | <a href="README_ZH.md">中文</a>
</p>

A local reaction, aiming and tracking benchmark built with Godot 4 for Windows, Linux and macOS. It measures the combined response of you and your computer.

## Getting started

Download your platform's package from [Releases](https://github.com/Nigh/SyncRateBench/releases), extract the complete package and launch the application. Keep the bundled resources alongside the executable. The application opens fullscreen; its interface is English-only.

- Select a test from the left side of the menu. `History` and `Settings` are in the Tools section.
- Press `Esc` to return to the menu from a test, or quit from the menu. On a result page, press `R` or click `Retry` to try again.
- Reaction keys are `Space`, `Z`, `X` and the arrow keys. The left mouse button also responds or fires.
- Complete all five tests, optionally enter a tag, then click `Save Session` on the menu to save the whole session.

## Tests

Each test has five rounds. Result pages show individual rounds, median, mean and sample standard deviation, plus a radar comparing the current result with the latest results from the other tests.

### 2D Reaction

Respond to a color change using a reaction key or the left mouse button. Each trial has a random 1–4 second wait and a one-second response window. Early input or a timeout invalidates the whole set. After a valid response, the next wait starts immediately.

### 3D Reaction

Look around a fixed low-poly room using the mouse, with a 180° horizontal range. After a random 1–4 second wait, a target crosses between covers within a one-second response window. Click while the target is inside the camera's view; aiming the crosshair directly at it is unnecessary. Early input or a timeout invalidates the whole set.

### OSU

Hit the fixed center green gate to arm a round. After a random 1–3 second wait, hit six numbered circles in order. Adjacent circles are equally spaced. Only the current circle and the next two are visible, at 100%, 60% and 30% opacity; non-adjacent circles may overlap.

The cursor must be on the expected circle when you click or press a reaction key. You can hit the current circle while it is still fading in. Timing runs from the first valid hit to the last, with a six-second limit after the first hit. Early input during the wait, a miss or an out-of-order hit invalidates the whole set. Missing the green gate does not invalidate it. After a successful round, the next gate appears immediately.

### 3D Aim

Aim at and hit the center green gate to arm a round. After a random 1–3 second wait, six non-overlapping spheres appear together. Five fixed layouts appear once each in shuffled order, covering all four view quadrants.

Aim with the mouse and fire using the left mouse button or a reaction key. Hit spheres disappear immediately. Timing runs from target appearance to the last hit. Early fire during the wait or failing to clear all targets within six seconds invalidates the whole set. Fires less than 150 ms apart are ignored; missing the green gate does not invalidate the set. After a successful clear, the next gate appears immediately.

### 3D Tracking

Track a moving target using only mouse look; no firing is required. Preparation starts automatically. Keep the crosshair inside the outer circle continuously for one second to start a 10-second scored round. Leaving the circle during preparation resets acquisition; the outer progress ring shows your progress.

The target moves slowly during preparation and returns to full speed over the first scored second. Five fixed paths appear once each in shuffled order. Time inside the yellow inner circle earns full credit, time in the outer ring earns half credit, and time outside earns zero. A quiet high/low tone indicates inner/outer coverage during scoring.

The raw result is the median time-weighted coverage percentage; higher is better. Mean angular error is also shown; lower is better. Losing the target reduces coverage. Losing window focus cancels the set, and returning starts a fresh set automatically. Keep display and frame-rate conditions consistent when comparing results.

## Scores

Each test converts its five-round raw median to 0–100 points, displayed to one decimal place. Raw milliseconds or weighted tracking coverage remain visible. Higher points are always better. The menu shows a total out of 500 when all five results are available; missing results appear as `--`.

| Test | Reference scores |
| --- | --- |
| 2D / 3D Reaction | 50 ms = 100, 220 ms = 80, 1000 ms = 0 |
| OSU | 500 ms = 100, 1800 ms = 70, 6000 ms = 0 |
| 3D Aim | 2400 ms = 60, 6000 ms = 0 |
| 3D Tracking | 0% coverage = 0, 30% = 60, 100% = 100 |

Reaction and OSU interpolate linearly in log(time) between these anchors. Aim uses `clamp(60 * ln(6000/t) / ln(6000/2400), 0, 100)`. Tracking uses `60 * ln(1+c) / ln(31)` for coverage `c <= 30`, then `60 + 40 * ln(c/30) / ln(100/30)`. All point scores are clamped to 0–100.

Invalid or timed-out sets show 0.0 points and do not replace cached results. A completed 0% Tracking result is valid.

## Sessions and history

The menu keeps the latest valid result for each test from the current app run, even if it is worse than the previous one. Each result can be saved for one hour after completion. Expired results remain visible with faded styling and an `EXPIRED` label, but cannot be saved.

`Save Session` requires five unexpired, unsaved results. An optional tag can contain up to 64 characters. Saving stores those five results as one session and clears the tag; scores and radar remain visible. Complete all five tests again to save another session. A failed save retains results for retry within their original save windows. Unsaved results are lost when the application exits.

`History` shows all sessions and explicitly labeled legacy single-test records, newest first, with 50 entries per page. Its chart shows the latest 100 entries chronologically on a fixed 0–100 point scale. Scroll, pan or drag horizontally to browse; hover a bar for individual rounds and metadata, or click a chart group or list row to select a session. Details include total points, per-test points and raw scores, sensitivity, rules versions and a radar. Legacy records show only their actual test, with points out of 100.

Sessions preserve each test's completion time, five samples, statistics, sensitivity and rules version, plus Tracking angular errors. Session save times include UTC, local time and UTC offset. Current rules versions are Reaction v1, OSU v3, Aim v2 and Tracking v4; check them when comparing results.

Settings are stored locally in `user://scores.txt`; saved history is in `user://history.json`. Valid older epoch-2 single-test records remain labeled as legacy records. Migration from valid pre-epoch-2 data discards old scores and history while preserving sensitivity. Damaged, unreadable or unsupported files are protected from overwriting. Cloud sync, history export, editing and deletion are not provided.

## Sensitivity and practice

All 3D modes share a sensitivity multiplier and a 103° horizontal field of view (about 70.5° vertically at 16:9). Sensitivity defaults to 1.00 and ranges from 0.10 to 5.00. Adjust it in `Settings`, or select `Open Sens Lab` for unscored practice: clear four spheres arranged in a square, then hit the center green gate to respawn them.

- Mouse wheel: adjust sensitivity by 0.05; hold `Alt` for 0.01 steps.
- Hold `Alt`: release the cursor to drag the sensitivity slider; release `Alt` to resume mouse look.
- `-` / `=`: decrease / increase square spacing.
- `[` / `]`: bring targets closer / move them farther away in 0.25 steps, from 3 to 20 (default 8).

Spacing and distance keys support holding for repeated adjustments. Spacing shrinks when needed to keep targets within view and prevent overlap. The bottom panel appears while adjusting and fades after inactivity. Sensitivity, spacing and distance are saved; a failed save restores the previous settings and layout.

## Interpreting results

SyncRateBench measures the **human + computer response chain**, including display, input and system latency. Useful comparisons keep one side fixed:

- Different people on the same computer: compare player response.
- The same person on different computers: compare device impact.
- The same person on the same computer over time: observe changes in form.

Scores from different people on different computers cannot isolate either factor. Timing uses Godot's monotonic microsecond clock, not a physical measurement of when photons reach the screen. Display scanout, pixel response, input polling and operating-system scheduling cannot be separated from the result. VSync and accumulated mouse input are disabled to reduce software latency; tearing may occur.

## Development and builds

Clone [SyncRateBench](https://github.com/Nigh/SyncRateBench) and open `project.godot` in Godot. The project uses GDScript, native Godot UI and 3D rendering, with no .NET requirement. The configured renderer is Compatibility. The release workflow uses Godot 4.4.1 with matching non-.NET export templates.

From the repository root, import the project and run the checks:

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script tests/reaction_state_test.gd
godot --headless --path . --script tests/sequence_state_test.gd
godot --headless --path . --script tests/playthrough_test.gd
godot --headless --path . --script tests/history_tracking_test.gd
```

Use the `Linux`, `Windows` or `macOS` export preset to build a release package. Distribute all export files, including separate `.pck` resources when present. macOS packages use the Universal template for Intel and Apple Silicon. Pull requests build packages for all three platforms; `v*` tags or manual release workflow runs publish releases.

## License and credits

[MIT](LICENSE). The interface uses the [xianii dark palette](https://github.com/Nigh/xianii-theme) and Maple Mono as its bundled font. Release packages include third-party notices: [Maple Mono SIL OFL 1.1](assets/MapleMono-OFL.txt) and [xianii-theme MIT](assets/licenses/xianii-theme-LICENSE.txt).
