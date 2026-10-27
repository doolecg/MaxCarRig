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
| Spline follow | A blue `<car>_CarRig_Path` helper with a Path Constraint (Follow, constant speed). Animate its Percent to change timing. |
| Body mode | Rays go down from the BOTTOM helper; the car sits on the hit point, tilted to the surface. |
| Per-wheel mode | One ray under each of four wheels; the car is fitted to the plane through the four hits, which is steadier on bumpy ground. |
| Several ground objects | The highest hit under each ray wins, so roads on top of terrain work. |
| No plugin needed to open scenes | The rig is a Transform Script controller saved in the .max file. |
| Remove rig | Unlinks the car (back to its old parent), deletes the rig helpers. Undo works. |

## Settings

Car front faces (world): which world axis the car's nose points along as it sits in the scene when you build. Ray start above spline: how far above the spline each ray starts. Keep it above the highest bump but below any bridge you drive under. The first gotcha: if the car sits sideways, the front axis is wrong; remove the rig and build again with the right one.

## Privacy

Nothing leaves your machine. The script makes no network calls and writes no files.

## Licence

MIT, see [LICENSE](LICENSE). Not affiliated with or endorsed by Autodesk. 3ds Max is a trademark of Autodesk, Inc.

## Disclaimer

This software is provided "as is", without warranty of any kind, as set out in the [LICENSE](LICENSE). To the extent permitted by law, the authors are not liable for any loss or damage from using it, including lost data, lost work or damage to files or projects. Nothing here limits liability that cannot be limited by law, such as for death or personal injury caused by negligence.

Back up your work before using it. You use it at your own risk.
