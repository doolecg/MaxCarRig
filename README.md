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
| Spline follow | The car rides the spline at constant speed. Progress % on the rig's Car Rig modifier is keyed 0 to 100 over the timeline; re-key it to change timing. |
| Simple mode | The car just rides the spline, pitched along it, at the BOTTOM height. No ground, steering or bank. |
| Body mode | Rays go down from the BOTTOM helper; the car sits on the hit point, tilted to the surface. |
| Per-wheel mode | One ray under each of four wheels; the car is fitted to the plane through the four hits, which is steadier on bumpy ground. |
| Front wheel steering | An orange `<car>_CarRig_Aim` null rides the spline Look ahead units in front. Both front wheels share one steering controller, so they always turn the same way, up to Max steer. |
| Bank | The body rolls with the steer angle on a `_CarRig_Bank` helper at axle height. Positive Bank leans out of the turn, negative leans in. |
| Wheel centre | Steering and wheel contacts use each wheel's pivot point or its bounding box centre, your choice. |
| Include or exclude ground | Include: only listed objects are ground. Exclude: every visible geometry object except the list and the car (a snapshot taken at Build). |
| Auto size | Rig helpers are sized from the car and wheel size. |
| No plugin needed to open scenes | The rig is a Transform Script controller saved in the .max file. |
| Car Rig modifier | The green `<car>_CarRig` rectangle round the car carries a Car Rig modifier with Progress %, Look ahead, Max steer, Bank and Ray start height. All live and animatable. |
| Remove rig | Unlinks the car and wheels (back to their old parents), deletes the rig helpers. Undo works. |

## Settings

Car front faces (world): which world axis the car's nose points along as it sits in the scene when you build. Ray start above spline: how far above the spline each ray starts. Keep it above the highest bump but below any bridge you drive under. The first gotcha: if the car sits sideways, the front axis is wrong; remove the rig and build again with the right one.

## Privacy

Nothing leaves your machine. The script makes no network calls and writes no files.

## Licence

MIT, see [LICENSE](LICENSE). Not affiliated with or endorsed by Autodesk. 3ds Max is a trademark of Autodesk, Inc.

## Disclaimer

This software is provided "as is", without warranty of any kind, as set out in the [LICENSE](LICENSE). To the extent permitted by law, the authors are not liable for any loss or damage from using it, including lost data, lost work or damage to files or projects. Nothing here limits liability that cannot be limited by law, such as for death or personal injury caused by negligence.

Back up your work before using it. You use it at your own risk.
