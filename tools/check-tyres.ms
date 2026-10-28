-- MaxCarRig check: where each tyre collision gizmo is compared with the tyre meshes.
-- Run: Scripting > Run Script. The report is copied to the clipboard; paste it to whoever asked for it.
(
	local ss = stringStream ""
	format "Frame %, units %\n" (sliderTime.frame as integer) units.SystemType to:ss
	for g in objects where matchPattern g.name pattern:"*_CarRig_Tyre*" do
		format "GIZMO % class:% pivot:% min:% max:% r:% h:% axis:% parent:%\n" g.name (classOf g) g.pos g.min g.max \
			(try (g.radius) catch ("-")) (try (g.height) catch ("-")) g.transform.row3 \
			(if g.parent == undefined then "-" else g.parent.name) to:ss
	for n in geometry where matchPattern n.name pattern:"*tire*" or matchPattern n.name pattern:"*tyre*" do
		format "TYRE % min:% max:% centre:%\n" n.name n.min n.max ((n.min + n.max) / 2) to:ss
	for n in objects where matchPattern n.name pattern:"*_CarRig_Spin*" or matchPattern n.name pattern:"*_CarRig_Susp*" do
		format "HELPER % pivot:%\n" n.name n.pos to:ss
	print (ss as string)
	setClipboardText (ss as string)
	messageBox "Tyre check copied to the clipboard." title:"Car Rig"
)
