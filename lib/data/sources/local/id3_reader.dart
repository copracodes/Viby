import 'dart:convert';
import 'dart:typed_data';

/// The three metadata fields Viby repairs, as read straight off disk.
///
/// Latin-1 frames are returned as Latin-1 strings *on purpose*: for legacy
/// Arabic files the frame bytes are really CP1256, and preserving them byte-for
/// -byte lets `bestDecoding` reinterpret them. UTF-16 / UTF-8 frames are decoded
/// properly (they're already correct and must not be touched).
class Id3Tags {
  const Id3Tags({this.title, this.artist, this.album});

  final String? title;
  final String? artist;
  final String? album;

  bool get isEmpty => title == null && artist == null && album == null;
}

/// A minimal, dependency-free ID3 tag reader (ID3v2.2/2.3/2.4 + ID3v1).
///
/// It extracts only the title/artist/album text frames — enough to repair
/// mojibake metadata. It is deliberately forgiving: any malformed structure
/// yields nulls rather than throwing, because it runs opportunistically over
/// arbitrary on-device files. Unsynchronisation and compressed/encrypted frames
/// are not handled (rare for text frames); such frames are skipped.
class Id3Reader {
  const Id3Reader._();

  /// Parses [bytes] (a whole file, or its head + tail) into [Id3Tags]. Prefers
  /// ID3v2 frames, falling back to ID3v1 for any field v2 didn't provide.
  static Id3Tags parse(Uint8List bytes) {
    final Id3Tags v2 = _parseV2(bytes);
    if (v2.title != null && v2.artist != null && v2.album != null) return v2;
    final Id3Tags v1 = _parseV1(bytes);
    return Id3Tags(
      title: v2.title ?? v1.title,
      artist: v2.artist ?? v1.artist,
      album: v2.album ?? v1.album,
    );
  }

  // --- ID3v2 --------------------------------------------------------------

  static Id3Tags _parseV2(Uint8List b) {
    if (b.length < 10 || b[0] != 0x49 || b[1] != 0x44 || b[2] != 0x33) {
      return const Id3Tags(); // no "ID3" magic
    }
    final int major = b[3];
    final int tagSize = _synchsafe(b, 6);
    final int end = (10 + tagSize).clamp(0, b.length);

    String? title;
    String? artist;
    String? album;

    int pos = 10;
    final bool v22 = major == 2;
    final int idLen = v22 ? 3 : 4;
    final int headerLen = v22 ? 6 : 10;

    while (pos + headerLen <= end) {
      // A padding zero where a frame id should be marks the end of frames.
      if (b[pos] == 0) break;
      final String id = _ascii(b, pos, idLen);
      final int size = v22
          ? _uint24(b, pos + 3)
          : (major == 4 ? _synchsafe(b, pos + 4) : _uint32(b, pos + 4));
      final int dataStart = pos + headerLen;
      final int dataEnd = dataStart + size;
      if (size <= 0 || dataEnd > end) break;

      if (_isTextFrame(id)) {
        final String? value = _decodeTextFrame(
          Uint8List.sublistView(b, dataStart, dataEnd),
        );
        if (value != null && value.isNotEmpty) {
          switch (id) {
            case 'TIT2':
            case 'TT2':
              title ??= value;
            case 'TPE1':
            case 'TP1':
              artist ??= value;
            case 'TALB':
            case 'TAL':
              album ??= value;
          }
        }
      }
      pos = dataEnd;
    }
    return Id3Tags(title: title, artist: artist, album: album);
  }

  static bool _isTextFrame(String id) => const <String>{
        'TIT2', 'TPE1', 'TALB', // v2.3 / v2.4
        'TT2', 'TP1', 'TAL', // v2.2
      }.contains(id);

  /// Decodes a text-frame body: byte 0 is the encoding, the rest is the string
  /// (trailing NUL trimmed). Latin-1 is preserved byte-for-byte (see [Id3Tags]).
  static String? _decodeTextFrame(Uint8List body) {
    if (body.isEmpty) return null;
    final int encoding = body[0];
    final Uint8List raw = Uint8List.sublistView(body, 1);
    switch (encoding) {
      case 0: // ISO-8859-1 (Latin-1) — keep the raw bytes as code units.
        return _trimNul(String.fromCharCodes(_stripTrailingNul(raw)));
      case 1: // UTF-16 with BOM.
        return _trimNul(_decodeUtf16(raw, null));
      case 2: // UTF-16BE, no BOM.
        return _trimNul(_decodeUtf16(raw, Endian.big));
      case 3: // UTF-8.
        try {
          return _trimNul(
            utf8.decode(_stripTrailingNul(raw), allowMalformed: true),
          );
        } catch (_) {
          return null;
        }
      default:
        return _trimNul(String.fromCharCodes(_stripTrailingNul(raw)));
    }
  }

  static String _decodeUtf16(Uint8List raw, Endian? forced) {
    if (raw.length < 2) return '';
    Endian endian = forced ?? Endian.little;
    int start = 0;
    if (forced == null) {
      if (raw[0] == 0xFF && raw[1] == 0xFE) {
        endian = Endian.little;
        start = 2;
      } else if (raw[0] == 0xFE && raw[1] == 0xFF) {
        endian = Endian.big;
        start = 2;
      }
    }
    final StringBuffer out = StringBuffer();
    for (int i = start; i + 1 < raw.length; i += 2) {
      final int unit = endian == Endian.big
          ? (raw[i] << 8) | raw[i + 1]
          : (raw[i + 1] << 8) | raw[i];
      if (unit == 0) break;
      out.writeCharCode(unit);
    }
    return out.toString();
  }

  // --- ID3v1 (last 128 bytes) ---------------------------------------------

  static Id3Tags _parseV1(Uint8List b) {
    if (b.length < 128) return const Id3Tags();
    final int base = b.length - 128;
    if (b[base] != 0x54 || b[base + 1] != 0x41 || b[base + 2] != 0x47) {
      return const Id3Tags(); // no "TAG" magic
    }
    // Fields are Latin-1 (really the file's legacy codepage) — preserve bytes.
    String field(int offset, int len) => _trimNul(
          String.fromCharCodes(
            _stripTrailingNul(
              Uint8List.sublistView(b, base + offset, base + offset + len),
            ),
          ),
        ).trim();
    final String title = field(3, 30);
    final String artist = field(33, 30);
    final String album = field(63, 30);
    return Id3Tags(
      title: title.isEmpty ? null : title,
      artist: artist.isEmpty ? null : artist,
      album: album.isEmpty ? null : album,
    );
  }

  // --- byte helpers -------------------------------------------------------

  /// 28-bit synchsafe integer (7 usable bits per byte) at [off].
  static int _synchsafe(Uint8List b, int off) =>
      (b[off] << 21) | (b[off + 1] << 14) | (b[off + 2] << 7) | b[off + 3];

  static int _uint32(Uint8List b, int off) =>
      (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

  static int _uint24(Uint8List b, int off) =>
      (b[off] << 16) | (b[off + 1] << 8) | b[off + 2];

  static String _ascii(Uint8List b, int off, int len) =>
      String.fromCharCodes(Uint8List.sublistView(b, off, off + len));

  /// Cuts the string at the first NUL (ID3 text after a NUL is not part of the
  /// value). Uses a char code so the delimiter can't be an invisible literal.
  static String _trimNul(String s) {
    final int nul = s.indexOf(String.fromCharCode(0));
    return nul >= 0 ? s.substring(0, nul) : s;
  }

  static Uint8List _stripTrailingNul(Uint8List raw) {
    int end = raw.length;
    while (end > 0 && raw[end - 1] == 0) {
      end--;
    }
    return Uint8List.sublistView(raw, 0, end);
  }
}
