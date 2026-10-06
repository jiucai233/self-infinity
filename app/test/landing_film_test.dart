// The front page's scroll film (app/tool/landing_frames.py): its track, and the still robot when
// there is none.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/features/auth/landing_page.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw StateError('no $key');
    return ByteData.sublistView(utf8.encode(text));
  }
}

void main() {
  const track = '${LandingFilm.folder}/track.json';

  test('no track: no film (the page shows the still robot)', () async {
    expect(await LandingFilm.load(_Bundle({})), isNull);
    expect(await LandingFilm.load(_Bundle({track: 'not json'})), isNull);
  });

  test('the orb between frames is in between; a frame without it borrows its neighbour', () async {
    final film = await LandingFilm.load(
      _Bundle({
        track: jsonEncode({
          'frames': 3,
          'aspect': 1.5,
          'orb': [
            [0.6, 0.6, 0.1],
            null,
            [0.4, 0.4, 0.3],
          ],
        }),
      }),
    );
    expect(film!.frames, 3);
    expect(film.frame(0, wide: true), '${LandingFilm.folder}/wide_000.webp');
    expect(film.frame(99, wide: false), '${LandingFilm.folder}/narrow_002.webp');
    expect(film.orbAt(0)!.r, closeTo(0.1, 1e-9));
    // Frame 1 has no orb: it reads as frame 0's, then moves to frame 2's.
    expect(film.orbAt(1)!.x, closeTo(0.6, 1e-9));
    expect(film.orbAt(1.5)!.x, closeTo(0.5, 1e-9));
    expect(film.orbAt(2)!.r, closeTo(0.3, 1e-9));
  });
}
