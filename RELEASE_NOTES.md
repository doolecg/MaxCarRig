# V1 Simple Car Rig 0.6.1

## New
- Auto detect by name: FRONT_LEFT, FRONT_RIGHT, BACK_LEFT, BACK_RIGHT, BODY, CAR PATH and CAR SURFACE.
- Per-wheel suspension, with Suspension and Travel on the Car Rig modifier.
- Realistic body motion: the body rises, pitches and rolls with the ground a few frames late (Body follow, Body lag).
- Bake a copy: instance copies of the car keyed on every frame, on their own layer, with a frame range, progress bar and Esc to cancel.
- Rig and car go on their own layer when built (optional); Remove puts everything back.
- Setup guide button, Speed test and Check steering buttons, and a log.

---

## Changed
- Playback is about 300 times faster: spline lookups come from a table built once instead of being re-measured every frame. Redraw went from about 4.7 seconds to about 14 ms per frame in testing.
- Steering reads only the spline: travel direction against the line to the look-ahead point.
- Wider dialog in two columns, in Max's own colours with the V1 header and version number.
- Look ahead defaults to 8 m.
- Licence: proprietary, Visualisation One.

---

## Fixed
- The car turns smoothly along the spline instead of in steps.
- Wheels spin about their own axle (pivot orientation) and brakes no longer spin.
- Front wheels no longer lock to one side.
- Build errors in Max 2026 ("Bad free thunk", group detach, reserved word).
