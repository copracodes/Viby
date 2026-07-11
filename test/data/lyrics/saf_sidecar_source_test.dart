import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/lyrics/lyrics_repository.dart';
import 'package:viby/data/lyrics/lyrics_saf_channel.dart';
import 'package:viby/data/lyrics/sources/saf_sidecar_source.dart';
import 'package:viby/data/models/track.dart';

class _FakeBridge implements LyricsSafBridge {
  _FakeBridge(this.bytes);
  Uint8List? bytes;
  String? lastTreeUri;
  String? lastAbsPath;
  String? lastSidecarName;

  @override
  Future<String?> pickFolder() async => 'content://tree/primary%3AMusic';

  @override
  Future<bool> hasAccess(String treeUri) async => true;

  @override
  Future<Uint8List?> readSidecar({
    required String treeUri,
    required String absPath,
    required String sidecarName,
  }) async {
    lastTreeUri = treeUri;
    lastAbsPath = absPath;
    lastSidecarName = sidecarName;
    return bytes;
  }
}

const Track _track = Track(
  id: 'local:1',
  source: TrackSource.local,
  title: 'T',
  albumId: 'a',
  artistId: 'ar',
  filePath: '/storage/emulated/0/Music/Artist/Song.mp3',
);

const String _treeUri = 'content://com.android.externalstorage.documents/tree/primary%3AMusic';

void main() {
  group('SafSidecarSource.resolve', () {
    test('reads a sidecar and computes the same-dir path + name', () async {
      final _FakeBridge bridge =
          _FakeBridge(Uint8List.fromList(utf8.encode('[00:01.00]Hi')));
      final SafSidecarSource source =
          SafSidecarSource(treeUri: _treeUri, bridge: bridge);

      final RawLyrics? raw = await source.resolve(_track);
      expect(raw, isNotNull);
      expect(raw!.source, LyricsSource.sidecarLrc);
      expect(raw.text, contains('[00:01.00]Hi'));
      expect(bridge.lastAbsPath, '/storage/emulated/0/Music/Artist/Song.lrc');
      expect(bridge.lastSidecarName, 'Song.lrc');
      expect(bridge.lastTreeUri, _treeUri);
    });

    test('returns null when no sidecar bytes come back', () async {
      final SafSidecarSource source =
          SafSidecarSource(treeUri: _treeUri, bridge: _FakeBridge(null));
      expect(await source.resolve(_track), isNull);
    });

    test('returns null for empty / whitespace-only bytes', () async {
      final SafSidecarSource ws = SafSidecarSource(
        treeUri: _treeUri,
        bridge: _FakeBridge(Uint8List.fromList(utf8.encode('   \n'))),
      );
      expect(await ws.resolve(_track), isNull);
    });

    test('returns null for a track with no local file (subsonic)', () async {
      const Track remote = Track(
        id: 'subsonic:s:1',
        source: TrackSource.subsonic,
        title: 'T',
        albumId: 'a',
        artistId: 'ar',
      );
      final SafSidecarSource source = SafSidecarSource(
        treeUri: _treeUri,
        bridge: _FakeBridge(Uint8List.fromList(<int>[1, 2, 3])),
      );
      expect(await source.resolve(remote), isNull);
    });

    test('legacy CP1256 bytes pass through decodeBytes for recovery', () async {
      // CP1256 bytes for "بحر" prefixed with an ASCII timestamp.
      final _FakeBridge bridge = _FakeBridge(Uint8List.fromList(<int>[
        ...'[00:02.00]'.codeUnits,
        0xC8, 0xCD, 0xD1,
      ]));
      final SafSidecarSource source =
          SafSidecarSource(treeUri: _treeUri, bridge: bridge);
      final RawLyrics? raw = await source.resolve(_track);
      // decodeBytes keeps the invalid-UTF-8 bytes as Latin-1 code units; the
      // repository's LrcParser then recovers the Arabic per line.
      expect(raw, isNotNull);
      expect(raw!.text, contains('[00:02.00]'));
    });
  });

  group('prettyTreeUriName', () {
    test('extracts the folder name from a tree URI', () {
      expect(prettyTreeUriName(_treeUri), 'Music');
    });

    test('takes the last path segment of a nested grant', () {
      expect(
        prettyTreeUriName(
          'content://com.android.externalstorage.documents/tree/primary%3AMusic%2FLyrics',
        ),
        'Lyrics',
      );
    });
  });
}
