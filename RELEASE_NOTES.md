# V1 Simple Car Rig 0.11.0

## New
- Corner speed: with Slow on corners on, the car never goes faster than each bend allows, brakes for bends at Braking g, keeps its speed if it is already slow enough, then pulls away again.
- Speed readout in km/h and mph from the scene units, top speed, and Set run from speed.
- Car Rig modifier split into six folding panels: presets, drive and speed, bank and dive, wheels, body, corners.
- Presets stay showing what was picked and are saved with the scene.

---

## Changed
- More bank on corners: V1 default 70 degrees per g, car types lean about 1.5 times more.
- Speed unit defaults to mph.
- Wider number boxes and shorter labels.

---

## Fixed
- Panels flickering while scrubbing (the speed readout now updates on a button).
- Speed readout error "Unknown property pos".

---

# V1 Simple Car Rig 0.9.6

## New
- Bank on turns from real cornering: speed squared times how sharp the bend is. Sharper and faster turns lean more.
- Dive and squat: the nose dips when braking and lifts when pulling away, with separate Start ease and Stop ease.
- Ease in / out: the car pulls away from rest and brakes to a stop before the end of the spline, still on your Progress keys.
- Corner slowdown (optional): the car slows into bends and makes the time up on straights.
- Presets on the Car Rig modifier: Car type (10 types), Suspension (soft, mid, hard) and Body look.
- Refresh selected rig: rebuilds from the same parts, keeping every modifier setting and the Progress keys.
- Check steering now also reports body and suspension numbers.

---

## Changed
- Bank and dive limits ease in softly (Max bank, Max dive / squat) and can be pushed far for a stylised look.
- Car Rig modifier laid out in short groups so no labels are cut off.
- Defaults: V1 look (bank 45 per g, 60-frame ease), 4 m look ahead.
- Spline edits are picked up automatically.

---

## Fixed
- Jittery banking: the lean now comes from the spline and Progress keys, not the bumpy ground fit.
- Ground rays that miss (spline under the road) try again from higher up.

---

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
