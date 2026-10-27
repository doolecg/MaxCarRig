# MaxCarRig

A 3ds Max script that turns a car model into a simple rig that drives along a spline and sits flat on your ground geometry.

## Get started in about 30 seconds

Needs 3ds Max 2017 or newer on Windows.

1. Drag `dist/V1_SimpleCarRig.mzp` onto a 3ds Max viewport (rebuild it with `powershell -File tools/build-mzp.ps1`), or use Scripting > Run Script and pick `CarRig.ms`.
2. Select the car, press Use selection as car, pick the spline, add the ground, press Create at car bottom.
3. Press Build rig and scrub the timeline.

That's it. The car now follows the spline from start to end over the active time range. The tool also adds an "SCR" button (V1 - Simple Car Rig) under category "V1_Scripts" for toolbars and hotkeys.

## What it does

| Capability | What you get |
| --- | --- |
| Auto detect by name | Finds FRONT_LEFT, FRONT_RIGHT, BACK_LEFT, BACK_RIGHT (or REAR_), BODY, CAR PATH and CAR SURFACE in the scene, and makes a BOTTOM helper. Spaces, dashes and case do not matter. |
| Bake a copy | Makes instance copies of the car keyed on every frame, on their own `<rig>_Baked` layer, and hides the live rig for lag-free playback. Unhide the rig to change it and bake again. |
| Spline follow | The car rides the spline at constant speed. Progress % on the rig's Car Rig modifier is keyed 0 to 100 over the timeline; re-key it to change timing. |
| Simple mode | The car just rides the spline, pitched along it, at the BOTTOM height. No ground, steering or bank. |
| Body mode | Rays go down from the BOTTOM helper; the car sits on the hit point, tilted to the surface. |
| Per-wheel mode | One ray under each of four wheels; the car is fitted to the plane through the four hits, which is steadier on bumpy ground. |
| Front wheel steering | An orange `<car>_CarRig_Aim` null rides the spline Look ahead units in front. Both front wheels share one steering controller, so they always turn the same way, up to Max steer. |
| Presets | On the Car Rig modifier: Car type (saloon, hatchback, sports car, supercar, muscle car, SUV, van, truck, buggy, classic), Suspension (soft, mid, hard) and Body look (V1 default, subtle, sporty, exaggerated, off). Every value can be changed after. |
| Ease in / out | The car pulls away from rest and brakes to a stop over Start frames and Stop frames (40 each by default), still leaving and arriving on your Progress keys. The body squats and dips with it. |
| Corner slowdown | Optional: the car spends longer in bends and makes it up on straights, braking before each bend; start and finish stay on your Progress keys. Amount, Tight radius and Brake dist on the modifier. |
| Suspension | Each wheel follows the ground under it on a `_CarRig_Susp` helper, up to Travel (half a wheel radius by default). Suspension 0 to 1 on the modifier sets how much. Body and Per wheel modes. |
| Realistic body motion | The body rises, falls, pitches and rolls with the ground a few frames late, like springs. Body follow (0 to 1) and Body lag (frames) on the modifier; untick Realistic body motion to turn it off. Bake for smooth playback. |
| Rig layer | Build puts the rig and car on a layer named after the rig (untick to leave them); Remove puts everything back on its old layer. |
| Tyre spin | Each picked wheel rolls by distance travelled / its radius, on a yellow `_CarRig_Spin` helper at the wheel centre. Tyre spin x on the modifier scales it (0 stops, above 1 gives wheelspin). |
| Front from wheels | With both front wheels picked, the rig works out which way the car faces from the wheels; the dropdown is only used without them. |
| Bank and dive / squat | The body leans out of turns and the nose lifts when speeding up and dips when braking, from the car's real motion along the spline. Bank and Dive / squat (degrees per g) on the modifier. |
| Wheel centre | Steering and wheel contacts use each wheel's pivot point or its bounding box centre, your choice. |
| Include or exclude ground | Include: only listed objects are ground. Exclude: every visible geometry object except the list and the car (a snapshot taken at Build). |
| Auto size | Rig helpers are sized from the car and wheel size. |
| No plugin needed to open scenes | The rig is a Transform Script controller saved in the .max file. |
| Car Rig modifier | The green `<car>_CarRig` rectangle round the car carries a Car Rig modifier with Progress %, Look ahead (4 m by default), Max steer, Bank, Ray start height and Reverse along spline (drive from the last vertex to the first, nose first). All live. |
| Remove rig | Unlinks the car and wheels (back to their old parents), deletes the rig helpers. Undo works. |

## Settings

Car front faces (world): which world axis the car's nose points along as it sits in the scene when you build. Ray start above spline: how far above the spline each ray starts. Keep it above the highest bump but below any bridge you drive under. The first gotcha: if the car sits sideways, the front axis is wrong; remove the rig and build again with the right one.

## Privacy

Nothing leaves your machine. The script makes no network calls and writes no files.

## Licence

Proprietary. Copyright (c) 2026 Visualisation One. All rights reserved; see [LICENSE](LICENSE). Not affiliated with or endorsed by Autodesk. 3ds Max is a trademark of Autodesk, Inc.

## Disclaimer

Copyright (c) 2026 Visualisation One. All rights reserved. No licence is granted to copy, change or share this code unless Visualisation One says so in writing.

This software is provided "as is", without warranty of any kind. To the extent permitted by law, the authors are not liable for any loss or damage from using it, including lost data, lost work or damage to files or projects. Nothing here limits liability that cannot be limited by law, such as for death or personal injury caused by negligence.

Back up your work before using it. You use it at your own risk.
