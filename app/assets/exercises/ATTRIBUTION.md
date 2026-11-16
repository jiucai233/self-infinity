# Exercise library: sources and licenses

`library.json` and the pictures in `img/` are built by `app/tool/exercise_library.py` from
**free-exercise-db** by Yuhonas: https://github.com/yuhonas/free-exercise-db
(pinned to commit `f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5`).

## Data

The exercise data (names, body part, equipment, level, muscles, English instructions) comes from
`dist/exercises.json` of free-exercise-db, which is released under **The Unlicense** (public
domain). free-exercise-db in turn builds on the earlier `exercises.json` dataset by OllieJennings:
https://github.com/OllieJennings/exercises.json

We picked 120 of its 876 exercises, mapped its fields to the app's own sets (body part, category,
equipment, unit), shortened some English names, and trimmed the English instructions.

## Images

The two frames per exercise come from `exercises/<id>/0.jpg` and `1.jpg` of the same repository,
resized to 320 px wide and re-encoded as WEBP. free-exercise-db does not state a separate license
for the images; they are distributed in the repository under its Unlicense, and they originate
from the OllieJennings/exercises.json source above. If you reuse them, check those two
repositories for the current terms.

## Translations

The Korean and Chinese (Simplified) names and instructions are our own translations of the English
dataset text, written for this app. They are not part of the upstream dataset.
