-- MaxCarRig: a simple car rig for 3ds Max.
-- The car follows a spline and sits flat on ground geometry, using either one
-- BOTTOM helper (body mode) or four wheel contact points (per-wheel mode).
-- Run this file once (Scripting > Run Script). It opens the tool and adds the
-- "SCR" action under category "V1_Scripts" for toolbars, menus and hotkeys.

macroScript V1_SimpleCarRig
category:"V1_Scripts"
toolTip:"V1 - Simple Car Rig"
buttonText:"SCR"
(
	global MaxCarRig_UI
	try (destroyDialog MaxCarRig_UI) catch ()

	rollout MaxCarRig_UI "Car Rig" width:240
	(
		local carNodes = #(), groundNodes = #(), wheelNodes = #(undefined, undefined, undefined, undefined)
		local pathShape = undefined, bottomNode = undefined

		-- Evaluated by the rig root's Transform Script controller every frame.
		-- It lives in the scene file, so the rig keeps working without this tool.
		local rigScript = @"(
	local grounds = #(GROUNDS)
	local rayUp = RAYUP
	local offs = #(OFFSETS)
	fn castDown grounds p rayUp =
	(
		local best = undefined
		local r = ray (p + [0,0,rayUp]) [0,0,-1]
		for g in grounds where isValidNode g do
		(
			local h = intersectRay g r
			if h != undefined and (best == undefined or h.pos.z > best.pos.z) do best = h
		)
		best
	)
	fn frameFrom x z pos =
	(
		local y = normalize (cross z x)
		matrix3 (cross y z) y z pos
	)
	local pt = pathNode.transform
	local fwd = normalize pt.row1
	if offs.count == 0 then
	(
		local h = castDown grounds pt.pos rayUp
		if h == undefined then frameFrom fwd [0,0,1] pt.pos
		else
		(
			local up = normalize h.dir
			if up.z < 0 do up = -up
			frameFrom fwd up h.pos
		)
	)
	else
	(
		local guess = frameFrom (normalize [fwd.x, fwd.y, 0]) [0,0,1] pt.pos
		local hits = for o in offs collect
		(
			local w = o * guess
			local h = castDown grounds w rayUp
			if h == undefined then w else h.pos
		)
		-- Wheel order is FL, FR, RL, RR: front minus rear is forward, left minus right is left.
		local x = (hits[1] + hits[2]) - (hits[3] + hits[4])
		local y = (hits[1] + hits[3]) - (hits[2] + hits[4])
		local tm = frameFrom (normalize x) (normalize (cross x y)) [0,0,0]
		local mid = (hits[1] + hits[2] + hits[3] + hits[4]) / 4
		local offMid = (offs[1] + offs[2] + offs[3] + offs[4]) / 4
		tm.row4 = mid - offMid * tm
		tm
	)
)"

		fn shapeFilt o = superClassOf o == Shape
		fn geoFilt o = superClassOf o == GeometryClass

		fn listText nodes = (
			local s = ""
			for i = 1 to nodes.count do s += (if i > 1 then ", " else "") + (nodes[i] as string)
			s
		)

		fn bboxOf nodes = (
			local bmin = nodes[1].min, bmax = nodes[1].max
			for n in nodes do (
				bmin = [amin bmin.x n.min.x, amin bmin.y n.min.y, amin bmin.z n.min.z]
				bmax = [amax bmax.x n.max.x, amax bmax.y n.max.y, amax bmax.z n.max.z]
			)
			#(bmin, bmax)
		)

		fn topLevel nodes = for n in nodes where findItem nodes n.parent == 0 collect n

		fn makeBottom cars = (
			local bb = bboxOf cars
			local c = (bb[1] + bb[2]) / 2
			Point name:(uniqueName "CarRig_BOTTOM") pos:[c.x, c.y, bb[1].z] size:(length (bb[2] - bb[1]) * 0.2) \
				box:true cross:true axisTripod:false centerMarker:false wirecolor:yellow
		)

		-- Rig root starts at BOTTOM, local X = car front, local Y = car left, Z = world up.
		fn startFrame bottom fwdIndex = (
			local fronts = #([1,0,0], [-1,0,0], [0,1,0], [0,-1,0])
			local x = fronts[fwdIndex]
			local z = [0,0,1]
			matrix3 x (cross z x) z bottom.pos
		)

		fn wheelContact w = [(w.min.x + w.max.x) / 2, (w.min.y + w.max.y) / 2, w.min.z]

		fn buildRig cars path grounds bottom fwdIndex rayUp wheels = (
			local tops = topLevel cars
			local base = tops[1].name
			local bb = bboxOf cars
			local diag = length (bb[2] - bb[1])
			local tm = startFrame bottom fwdIndex
			local offs = for w in wheels collect (wheelContact w) * (inverse tm)

			local root = Point name:(uniqueName (base + "_CarRig")) transform:tm size:(diag * 0.6) \
				box:false cross:false axisTripod:true centerMarker:false wirecolor:green
			for n in tops + #(bottom) do (
				setUserProp n "MaxCarRig_oldParent" (if n.parent == undefined then 0 else n.parent.handle)
				n.parent = root
			)

			local mover = Point name:(uniqueName (base + "_CarRig_Path")) size:(diag * 0.2) \
				box:false cross:true axisTripod:false centerMarker:false wirecolor:blue
			local pc = Path_Constraint()
			mover.position.controller = pc
			pc.appendTarget path 100.0
			pc.follow = true
			pc.constantVel = true
			pc.axis = 0

			local s = substituteString rigScript "GROUNDS" (listText (for i = 1 to grounds.count collect ("g" + i as string)))
			s = substituteString s "RAYUP" (rayUp as string)
			s = substituteString s "OFFSETS" (listText offs)
			local ctrl = transform_script()
			root.transform.controller = ctrl
			ctrl.AddNode "pathNode" mover
			for i = 1 to grounds.count do ctrl.AddNode ("g" + i as string) grounds[i]
			ctrl.script = s

			setUserProp root "MaxCarRig" true
			setUserProp root "MaxCarRig_path" mover.handle
			root
		)

		fn removeRig root = (
			local mover = maxOps.getNodeByHandle (getUserProp root "MaxCarRig_path")
			for c in (for c in root.children collect c) do (
				local h = getUserProp c "MaxCarRig_oldParent"
				c.parent = if h == undefined or h == 0 then undefined else maxOps.getNodeByHandle h
			)
			if isValidNode mover do delete mover
			delete root
		)

		group "1. Car"
		(
			button btnCar "Use selection as car" width:210
			label lblCar "No car set" align:#left
		)
		group "2. Path"
		(
			pickbutton pbPath "Pick spline" filter:shapeFilt autoDisplay:true width:210
		)
		group "3. Ground"
		(
			listbox lbGround height:4
			button btnGroundAdd "Add selected" across:2 width:100
			button btnGroundClear "Clear" width:100
		)
		group "4. BOTTOM"
		(
			button btnBottomMake "Create at car bottom" width:210
			pickbutton pbBottom "Or pick BOTTOM" autoDisplay:true width:210
		)
		group "5. Options"
		(
			dropdownlist ddFwd "Car front faces (world)" items:#("+X", "-X", "+Y", "-Y")
			spinner spRay "Ray start above spline" range:[0, 1e6, 200] type:#worldunits
			radiobuttons rbMode labels:#("Body (BOTTOM)", "Per wheel") columns:1 align:#left
			pickbutton pbFL "Front left wheel" autoDisplay:true width:210 enabled:false
			pickbutton pbFR "Front right wheel" autoDisplay:true width:210 enabled:false
			pickbutton pbRL "Rear left wheel" autoDisplay:true width:210 enabled:false
			pickbutton pbRR "Rear right wheel" autoDisplay:true width:210 enabled:false
		)
		button btnBuild "Build rig" width:210 height:28
		button btnRemove "Remove selected rig" width:210
		group "About"
		(
			label lblA1 "Provided \"as is\", without warranty, under" align:#left
			label lblA2 "the MIT licence. To the extent permitted" align:#left
			label lblA3 "by law, the authors are not liable for" align:#left
			label lblA4 "any loss or damage from using it." align:#left
			label lblA5 "Back up your work." align:#left
		)

		on btnCar pressed do (
			carNodes = for o in selection collect o
			lblCar.text = if carNodes.count == 0 then "No car set" else (carNodes.count as string + " object(s): " + carNodes[1].name)
		)
		on pbPath picked o do pathShape = o
		on btnGroundAdd pressed do (
			for o in selection where geoFilt o and findItem groundNodes o == 0 do append groundNodes o
			lbGround.items = for g in groundNodes collect g.name
		)
		on btnGroundClear pressed do (
			groundNodes = #()
			lbGround.items = #()
		)
		on btnBottomMake pressed do (
			carNodes = for n in carNodes where isValidNode n collect n
			if carNodes.count == 0 then messageBox "Set the car first." title:"Car Rig"
			else (
				undo "Create BOTTOM" on (bottomNode = makeBottom carNodes)
				pbBottom.object = bottomNode
				select bottomNode
			)
		)
		on pbBottom picked o do bottomNode = o
		on rbMode changed s do for b in #(pbFL, pbFR, pbRL, pbRR) do b.enabled = (s == 2)
		on pbFL picked o do wheelNodes[1] = o
		on pbFR picked o do wheelNodes[2] = o
		on pbRL picked o do wheelNodes[3] = o
		on pbRR picked o do wheelNodes[4] = o

		on btnBuild pressed do (
			carNodes = for n in carNodes where isValidNode n collect n
			groundNodes = for n in groundNodes where isValidNode n collect n
			local err = case of (
				(carNodes.count == 0): "Set the car first: select it and press Use selection as car."
				(not isValidNode pathShape): "Pick the spline."
				(groundNodes.count == 0): "Add at least one ground object."
				(not isValidNode bottomNode): "Create or pick the BOTTOM helper."
				(findItem carNodes bottomNode != 0): "BOTTOM must not be part of the car selection."
				((for g in groundNodes where findItem carNodes g != 0 collect g).count > 0): "A ground object is part of the car."
				((for n in carNodes where n.parent != undefined and getUserProp n.parent "MaxCarRig" == true collect n).count > 0): "This car is already rigged. Remove the rig first."
				(rbMode.state == 2 and (for w in wheelNodes where isValidNode w collect w).count < 4): "Pick all four wheels."
				default: undefined
			)
			if err != undefined then messageBox err title:"Car Rig"
			else (
				local wheels = if rbMode.state == 2 then wheelNodes else #()
				undo "Build car rig" on (
					local root = buildRig carNodes pathShape groundNodes bottomNode ddFwd.selection spRay.value wheels
					select root
				)
			)
		)

		on btnRemove pressed do (
			local roots = for o in selection where getUserProp o "MaxCarRig" == true collect o
			if roots.count == 0 then messageBox "Select a rig first (the green ..._CarRig helper)." title:"Car Rig"
			else if queryBox ("Remove " + roots.count as string + " rig(s)? The car stays where it is on the current frame and the path helper is deleted.") title:"Car Rig" do
				undo "Remove car rig" on (for r in roots do removeRig r)
		)
	)

	on execute do createDialog MaxCarRig_UI
)

macros.run "V1_Scripts" "V1_SimpleCarRig"
