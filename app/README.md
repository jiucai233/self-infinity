# self_infinity (Flutter client)

The stage UI of Self-Infinity: `docs/ux-chat.md` (what exists), `docs/DESIGN.md`
(how it looks: light, Notion / ChatGPT-like).

```
flutter run -d chrome --dart-define=USE_FAKE_API=true                       # no backend
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api  # real backend
flutter analyze && flutter test
```

Routes: `/` (scene 1 / 5), `/map` (2), `/skill/:id` (4), `/skill/:id/audit` (4-1).

`flutter test test/screenshots_test.dart` renders every scene to PNG only when
`SHOTS_DIR` is set (see the file).
