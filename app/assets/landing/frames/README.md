# Front page frames

`app/tool/landing_frames.py <video>` fills this folder (the command used for the current video is in docs/DESIGN.md): `wide_NNN.webp` / `narrow_NNN.webp` (the
robot video, one picture per scroll step) and `track.json` (where the orb is in each). Without
`track.json` the front page shows the still robot (`../robot.png`) instead.
