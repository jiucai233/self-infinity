import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/app/app_state.dart';

void main() {
  test('markDataChanged raises the revision and notifies', () {
    final state = AppState();
    var calls = 0;
    state.addListener(() => calls++);
    expect(state.dataRevision, 0);
    state.markDataChanged();
    state.markDataChanged();
    expect(state.dataRevision, 2);
    expect(calls, 2);
  });
}
