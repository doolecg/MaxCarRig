<h1 align="center">V1 Simple Car Rig</h1>

<p align="center">
  <strong>Put any car model on a spline in 3ds Max and it drives like a real one.</strong><br>
  It sits on the road, steers to a point ahead, spins its wheels, rides kerbs on its suspension, leans and dives.<br>
  No physics to babysit: the same result every time you scrub or render. Nothing leaves your computer.
</p>

<p align="center">
  <a href="LICENSE"><img alt="Licence: proprietary" src="https://img.shields.io/badge/licence-proprietary-f2a516?style=flat-square&labelColor=161616"></a>
  <img alt="3ds Max 2017 or newer" src="https://img.shields.io/badge/3ds%20Max-2017%2B-f2a516?style=flat-square&labelColor=161616">
  <img alt="Version 0.25.1" src="https://img.shields.io/badge/version-0.25.1-f2a516?style=flat-square&labelColor=161616">
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#why-use-it">Why use it</a> ·
  <a href="#features">Features</a> ·
  <a href="docs/guide.md">Full guide</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#development">Development</a>
</p>

---

Animating a car by hand means keying the body, four wheels, steering, suspension and body roll, then doing it all again when the road changes. **This tool rigs the car to a spline instead.** Every frame is worked out from the spline, the ground and one Progress value, so it plays the same in the viewport, on a render farm and after a bake.

## Quick start

Needs 3ds Max 2017 or newer on Windows.

1. Drag `dist/V1_SimpleCarRig.mzp` onto a 3ds Max viewport. The tool opens, and an SCR button is added under the V1_Scripts category for toolbars and hotkeys.
2. Name your parts BODY, FRONT_LEFT, FRONT_RIGHT, BACK_LEFT and BACK_RIGHT, the spline CAR PATH and the road CAR SURFACE.
3. Press Auto detect by name, then Build rig, and play.

That's it. The car drives the spline over the timeline. Select the green `<car>_CarRig` rectangle to change speed, steering, suspension and more on its Car Rig modifier. No spline or ground yet? Build still works: the car rides a straight 30 m spline until you pick the real ones.

## Why use it

**Believable in minutes.** Auto detect finds the parts by name and makes the BOTTOM helper. Presets for car type, suspension and body look give a good feel before you touch a setting.

**Safe in your scenes.** The rig is a set of script controllers saved in the .max file, so a rigged scene opens and plays on a PC without the tool. Remove puts the car back where it was, on its old layers and in its old groups.

**Fast to play back.** Bake a copy makes a keyed copy of the car on its own layer for smooth viewport playback and render farms, and hides the live rig until you need it again.

## Features

| Capability | What you get |
| --- | --- |
| Spline follow | The car drives the spline; Progress % is keyed 0 to 100 over the timeline, or set from a cruise speed in km/h or mph. Keep speed re-times the run when the spline changes. |
| Ground fit | Simple (spline only), Body (one BOTTOM point) or Per wheel (four round, wide tyre contacts that roll up kerbs smoothly). |
| Steering and wheels | Front wheels steer to a point ahead with Ackermann geometry; the rear axle tracks the spline; each wheel spins by the distance it travels. |
| Suspension | Each wheel follows the ground under it within its travel; the body rides on a damped spring and lags a few frames, like real springs. |
| Body motion | Banks in turns, dives when braking and squats when pulling away, with ease times and maximum angles. |
| Speed control | Ease in and out, slow on corners (brakes for tight bends at a set g), slow for kerbs and bumps, and path smoothing for a cleaner line through bends. |
| Cameras | Standard, V-Ray Physical or 3ds Max Physical cameras that ride with the car, with a stabiliser and a level horizon; or attach any camera you already have. |
| Bake and remove | Bake a keyed copy for smooth playback; Remove puts the car back exactly as it was. |

## Privacy

Nothing leaves your computer. The tool makes no network calls. It writes one file: a log, `V1_SimpleCarRig.log` in 3ds Max's temp folder, which Open log shows you.

## Development

The whole tool is one file, `CarRig.ms`. Its layout is listed at the top of the file. Build the installer into `dist/` with:

```powershell
powershell -File tools/build-mzp.ps1    # dist\V1_SimpleCarRig.mzp
```

`tools/test-scene.ms` builds a test scene at real-world size: a street with a cambered road, a hump, dropped kerbs, a test car named for Auto detect and two paths. It resets the scene, asking you to save first. How the parts fit together is in [docs/systems.md](docs/systems.md), the reasons behind them in [docs/design.md](docs/design.md), and the user guide in [docs/guide.md](docs/guide.md).

## Licence

Proprietary. Copyright (c) 2026 Visualisation One. All rights reserved; see [LICENSE](LICENSE). Not affiliated with or endorsed by Autodesk. 3ds Max is a trademark of Autodesk, Inc.

## Disclaimer

Copyright (c) 2026 Visualisation One. All rights reserved. No licence is granted to copy, change or share this code unless Visualisation One says so in writing.

This software is provided "as is", without warranty of any kind. To the extent permitted by law, the authors are not liable for any loss or damage from using it, including lost data, lost work or damage to files or projects. Nothing here limits liability that cannot be limited by law, such as for death or personal injury caused by negligence.

Back up your work before using it. You use it at your own risk.
