# Front page robot (three.js)

`index.html` + `scene.js`: the robot on the front page, embedded by
`lib/features/auth/landing_robot_web.dart`. Design: docs/DESIGN.md, landing page.

- `xbot.glb`: three.js r170 `examples/models/gltf/Xbot.glb` (Mixamo's X Bot). Mixamo characters
  are royalty-free for personal and commercial projects; they may not be redistributed as a
  standalone model.
- three.js 0.170.0 (MIT) is loaded from jsDelivr by the import map in `index.html`.
- `?p=2.5` on the URL shows one moment of the scroll (0 the hero, 5 the end), for checking the look.
