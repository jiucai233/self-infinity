# 13주 · 실기기에서 돌리기, 설치하기

GAI3008 13주 실습(실기기 디버깅 · 릴리스 설치 · Human-in-the-Loop)을 Self-Infinity로 하는 방법.
루프 기록은 [`loop_log.md`](loop_log.md)에 남긴다.

## 설치본의 정체성

| 항목 | 값 | 위치 |
|---|---|---|
| applicationId / Bundle ID | `com.yonsei.gai3008.selfinfinity` | `app/android/app/build.gradle.kts` · Xcode |
| 버전 | `1.0.0+1` | `app/pubspec.yaml` |
| 앱 이름 | `Self-Infinity` | `AndroidManifest.xml`의 `android:label` · iOS `CFBundleDisplayName` |
| 아이콘 | 우리 로고 | `mipmap-*` · `Assets.xcassets` |

## 1. 폰 연결

```bash
flutter devices          # 내 폰 이름이 보이면 성공
```

Android는 개발자 옵션에서 USB 디버깅을 켜고 폰에서 '허용'을 누른다. iPhone은 Mac + Xcode에서 개인 Apple ID로 서명하고 개발자 모드를 켠다.

## 2. 서버 없이 (가장 간단: Judge용, 설치 시연용)

앱 안의 데모 데이터로 돈다. 서버도 Wi-Fi도 필요 없다.

```bash
cd app
flutter run --dart-define=USE_FAKE_API=true                       # debug: hot reload
flutter run --profile --dart-define=USE_FAKE_API=true             # 애니메이션 끊김 확인
flutter build apk --release --dart-define=USE_FAKE_API=true       # 설치본
flutter install
```

## 3. 배포된 서버에 붙이기 (추천)

웹과 같은 백엔드(`https://self-infinity.vercel.app/api`)에 HTTPS로 붙는다. 같은 Wi-Fi도, 노트북 IP도, 평문 HTTP 예외도 필요 없다. 계정도 웹과 같다(이메일 로그인).

```bash
scripts/build_phone.sh run        # debug, hot reload
scripts/build_phone.sh profile    # 끊김 확인
scripts/build_phone.sh apk        # 릴리스 APK 빌드 + flutter install
scripts/build_phone.sh ios        # iPhone에 release로 실행
```

- 설정은 `app/phone.json`에서 읽는다(git에 올리지 않음): `API_BASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`(publishable key). 팀원은 이 파일을 따로 받는다.
- 실제 LLM을 부르므로 비용이 든다. 판정·설치 시연만이면 2번(서버 없이)이 낫다.
- Google 로그인은 Supabase의 Redirect URLs에 `selfinfinity://login-callback`이 있어야 앱으로 돌아온다. 없으면 이메일 로그인을 쓴다.

## 4. 노트북 서버에 붙이기

폰에서 `127.0.0.1`은 폰 자신이다. 노트북의 Wi-Fi IP를 쓴다.

```bash
ipconfig getifaddr en0                                            # macOS: 노트북 IP (예: 192.168.0.10)
cd backend && LLM_PROVIDER=mock .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
cd app && flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8000/api
```

- 확인 순서: 폰 브라우저에서 `http://192.168.0.10:8000/docs`가 열리면 앱도 붙는다.
- `--host 0.0.0.0`은 수업 중에만. 로컬은 로그인 없는 dev 모드라 같은 Wi-Fi의 누구나 접근할 수 있다. `run.sh`는 그래서 `127.0.0.1`로 둔다.
- 학교 Wi-Fi가 기기끼리 통신을 막으면 노트북 핫스팟을 쓴다.
- HTTP 평문: Android `usesCleartextTraffic="true"`, iOS `NSAllowsLocalNetworking`(로컬 주소만). 실제 출시는 HTTPS.
- INTERNET 권한은 `src/main/AndroidManifest.xml`에 있다. 그래서 release에서도 통신이 된다.

## 5. Loop 1 애니메이션: 심사 대화에 새 줄이 들어올 때

- 무엇: 심사관의 새 질문이나 내 답이 대화에 들어올 때, 그 한 줄이 페이드인하며 12px 올라온다 (`app/lib/widgets/enter_in.dart`, 심사 화면 `audit_scene.dart`).
- 길이: 220ms, `Curves.easeOutCubic`. 이미 있던 줄(이어서 하는 심사)은 움직이지 않는다. 한 번에 한 줄만.
- 동작 줄이기: `MediaQuery.disableAnimationsOf(context)`가 켜져 있으면 바로 결과 상태. 아래로 따라가는 스크롤도 미끄러지지 않고 바로 이동.
- 테스트: `app/test/enter_in_test.dart`.

Judge 체크리스트(폰에서, profile 모드):

| 항목 | 확인 |
|---|---|
| 의미 | 새로 들어온 줄이 무엇인지 알려 주나? |
| 길이 | 200–250ms 안인가? |
| 하나 | 한 번에 한 줄만 움직이나? |
| 끊김 | profile Performance Overlay에 빨간 막대가 없나? |
| 접근성 | 애니메이션 삭제(Android) / 동작 줄이기(iOS)를 켜면 바로 끝나나? |

## 6. 설치 증거

홈 화면 아이콘 + 앱 첫 화면 사진 1장을 `docs/install.jpg`로 커밋한다.
