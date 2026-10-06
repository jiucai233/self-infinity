import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/auth/auth_service.dart';
import 'package:self_infinity/app/panel_layout.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/testing/fake_file_picker.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/testing/test_app.dart';

const Size wideScreen = Size(1440, 900);
const Size phoneScreen = Size(390, 844);

/// Mounts [child] like the app does, at [size] (a desktop window by default).
/// Other routes become `route:<location>` placeholders.
Future<void> pumpScene(
  WidgetTester tester,
  Widget child, {
  required SelfInfinityApi api,
  Size size = wideScreen,
  AppState? state,
  FakeVoiceService? voice,
  FakeFilePicker? picker,
  PanelLayout? layout,
  DateTime Function()? clock,
  AuthService? auth,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox()); // a fresh tree: no state from an earlier pump
  await tester.pumpWidget(
    buildTestApp(
      child: child,
      api: api,
      state: state,
      voice: voice,
      filePicker: picker,
      layout: layout,
      clock: clock,
      auth: auth,
    ),
  );
  await tester.pumpAndSettle();
}

/// Pumps scene 2 and switches it to the outline view (the layered graph of
/// the newest course).
Future<void> pumpOutline(
  WidgetTester tester, {
  required SelfInfinityApi api,
  Size size = wideScreen,
  AppState? state,
}) async {
  await pumpScene(tester, const MapScene(), api: api, size: size, state: state);
  await tester.tap(find.byKey(const Key('view-outline')));
  await tester.pumpAndSettle();
}

/// Types [text] into the stage input (without sending).
Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('stage-input')), text);
  await tester.pump();
}

/// Types [text] and sends it with the → button.
Future<void> say(WidgetTester tester, String text) async {
  await type(tester, text);
  await tester.tap(find.byKey(const Key('send')));
  await tester.pumpAndSettle();
}

String inputText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const Key('stage-input'))).controller!.text;

/// Every text shown inside [finder]'s widgets.
Iterable<String> textsIn(WidgetTester tester, Finder scope) => tester
    .widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text)))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');
