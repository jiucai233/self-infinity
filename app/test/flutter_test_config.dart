import 'dart:async';

import 'package:self_infinity/api/fake_api.dart';

/// Runs before every test file: fakes made without a clock start at 10:00 KST
/// today and go on from there, so the day's plan (it follows the time of day)
/// is a morning plan whatever hour the tests run at.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final started = DateTime.now().toUtc();
  final kst = started.add(const Duration(hours: 9));
  final morning = DateTime.utc(kst.year, kst.month, kst.day, 1); // 10:00 KST
  FakeApiClient.defaultClock = () => morning.add(DateTime.now().toUtc().difference(started));
  await testMain();
}
