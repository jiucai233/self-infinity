# 大肥鱼 (the agents' character)

作者：YunYueSama
仓库：https://github.com/YunYueSama/codex-deepseek-pet

Used under the 大肥鱼项目署名许可 1.0 (full text in LICENSE.txt), which allows use, modification and
commercial use with this attribution.

## What was modified

`dafeiyu.webp` is the only picture the app ships. It is an atlas of 29 frames (8 columns x 4 rows of
352 x 432 px cells) cut from these files of the repository's `assets/whale/` (512 px cells unless noted):

| Cells | Source file and cells (row-major) | Used for |
| --- | --- | --- |
| 0-8 | `expressions.png` 0, 1, 3, 6, 7, 8, 10, 9, 5 | neutral, curious, stern, holding her ball, happy, thinking, pouting, surprised, looking aside |
| 9-13 | `actions.png` 4, 5, 7, 2, 3 | smile, talking (open, smiling), thinking (finger on chin) |
| 14-15 | `idle-front.png` left and right halves (1024 px) | idle, eyes open / closed (the blink) |
| 16-19 | `motion-idle.png` 0, 2, 6, 13 | listening (looking around, head tilts) |
| 20-28 | `dense-wave.png` 6, 8, ..., 22 | the wave |

Modifications: each frame is cut out of its sheet and rescaled with Lanczos so a standing figure is the
same height in every cell (expressions x1.00, actions x0.98, motion-idle x0.98, dense-wave x0.95,
idle-front x0.48, fitted on each sheet's neutral frame), placed with her soles on one line and centred
as in the source, packed into the atlas and encoded as lossy WebP (`cwebp -q 86 -alpha_q 100 -m 6
-sharp_yuv`). Nothing in the drawings was altered. (Earlier versions of the app shipped
`expressions.webp`, the expression sheet downscaled to 256 px cells, and the repository's
`codex-deepseek-pet/spritesheet-web.webp`; both are gone.)

The license covers the author's own contributions only. The character is a community fan design of the
DeepSeek "whale girl"; it grants no rights to the underlying character design or to DeepSeek's marks, and
this app is not endorsed by YunYueSama or DeepSeek.
