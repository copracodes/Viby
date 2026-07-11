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

/// One timed entry of an ID3 `SYLT` (synchronised lyrics) frame.
class SyltEntry {
  const SyltEntry(this.timeMs, this.text);
  final int timeMs;
  final String text;
}

/// Embedded lyrics extracted from an audio file's ID3 tag.
///
/// [unsyncedText] is the raw `USLT` text; like [Id3Tags], a Latin-1 frame is
/// kept byte-for-byte so `bestDecoding`/`LrcParser` can recover legacy CP1256
/// Arabic. [syncedEntries] holds `SYLT` millisecond entries when present (rare);
/// a MPEG-frame-timed SYLT is treated as unsupported (null).
class EmbeddedLyrics {
  const EmbeddedLyrics({this.unsyncedText, this.syncedEntries});

  final String? unsyncedText;
  final List<SyltEntry>? syncedEntries;

  bool get isEmpty =>
      (unsyncedText == null || unsyncedText!.isEmpty) &&
      (syncedEntries == null || syncedEntries!.isEmpty);
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

  /// Extracts embedded lyrics (`USLT`/`ULT` unsynced, `SYLT`/`SLT` synced) from
  /// an ID3v2 tag. Returns empty when the tag carries no lyrics frame. Never
  /// throws — any structural oddity yields empty/partial results.
  static EmbeddedLyrics parseLyrics(Uint8List b) {
    if (b.length < 10 || b[0] != 0x49 || b[1] != 0x44 || b[2] != 0x33) {
      return const EmbeddedLyrics();
    }
    final int major = b[3];
    final int tagSize = _synchsafe(b, 6);
    final int end = (10 + tagSize).clamp(0, b.length);

    String? unsynced;
    List<SyltEntry>? synced;

    int pos = 10;
    final bool v22 = major == 2;
    final int idLen = v22 ? 3 : 4;
    final int headerLen = v22 ? 6 : 10;

    while (pos + headerLen <= end) {
      if (b[pos] == 0) break;
      final String id = _ascii(b, pos, idLen);
      final int size = v22
          ? _uint24(b, pos + 3)
          : (major == 4 ? _synchsafe(b, pos + 4) : _uint32(b, pos + 4));
      final int dataStart = pos + headerLen;
      final int dataEnd = dataStart + size;
      if (size <= 0 || dataEnd > end) break;
      final Uint8List body = Uint8List.sublistView(b, dataStart, dataEnd);

      if (id == 'USLT' || id == 'ULT') {
        unsynced ??= _decodeUsltText(body);
      } else if (id == 'SYLT' || id == 'SLT') {
        synced ??= _decodeSylt(body);
      }
      pos = dataEnd;
    }
    return EmbeddedLyrics(unsyncedText: unsynced, syncedEntries: synced);
  }

  /// Decodes a `USLT` body: enc(1) + language(3) + null-terminated descriptor +
  /// the lyrics text (rest). Latin-1 text is preserved byte-for-byte.
  static String? _decodeUsltText(Uint8List body) {
    if (body.length < 5) return null;
    final int enc = body[0];
    // Skip enc(1) + lang(3), then the descriptor up to its terminator.
    final int textStart = _afterNullTerminated(body, 4, enc);
    if (textStart >= body.length) return null;
    final String text =
        _decodeString(Uint8List.sublistView(body, textStart), enc);
    return text.isEmpty ? null : text;
  }

  /// Decodes a `SYLT` body. Only millisecond-timestamped (`timeFormat == 2`)
  /// frames are supported; anything else (MPEG-frame timing) yields null.
  static List<SyltEntry>? _decodeSylt(Uint8List body) {
    if (body.length < 7) return null;
    final int enc = body[0];
    final int timeFormat = body[4];
    if (timeFormat != 2) return null; // only absolute milliseconds
    int pos = _afterNullTerminated(body, 6, enc); // skip content-type + desc
    final List<SyltEntry> out = <SyltEntry>[];
    while (pos < body.length) {
      final int textEnd = _nullTerminatorIndex(body, pos, enc);
      if (textEnd < 0 || textEnd + _nullWidth(enc) + 4 > body.length) break;
      final String text =
          _decodeString(Uint8List.sublistView(body, pos, textEnd), enc);
      final int stampStart = textEnd + _nullWidth(enc);
      final int ms = _uint32(body, stampStart);
      out.add(SyltEntry(ms, text));
      pos = stampStart + 4;
    }
    return out.isEmpty ? null : out;
  }

  /// Decodes an arbitrary text run under ID3 [encoding] (0 Latin-1, 1 UTF-16
  /// w/ BOM, 2 UTF-16BE, 3 UTF-8). Latin-1 is preserved byte-for-byte.
  static String _decodeString(Uint8List raw, int encoding) {
    switch (encoding) {
      case 1:
        return _decodeUtf16(raw, null);
      case 2:
        return _decodeUtf16(raw, Endian.big);
      case 3:
        try {
          return utf8.decode(raw, allowMalformed: true);
        } catch (_) {
          return '';
        }
      default:
        return String.fromCharCodes(raw);
    }
  }

  /// The width in bytes of a NUL terminator for [encoding] (2 for UTF-16).
  static int _nullWidth(int encoding) => (encoding == 1 || encoding == 2) ? 2 : 1;

  /// Index of the NUL terminator at/after [from] for [encoding], or -1 if none.
  static int _nullTerminatorIndex(Uint8List b, int from, int encoding) {
    if (encoding == 1 || encoding == 2) {
      for (int i = from; i + 1 < b.length; i += 2) {
        if (b[i] == 0 && b[i + 1] == 0) return i;
      }
      return -1;
    }
    for (int i = from; i < b.length; i++) {
      if (b[i] == 0) return i;
    }
    return -1;
  }

  /// The index just past a null-terminated field starting at [from] under
  /// [encoding]. If no terminator is found, returns the buffer length.
  static int _afterNullTerminated(Uint8List b, int from, int encoding) {
    final int t = _nullTerminatorIndex(b, from, encoding);
    return t < 0 ? b.length : t + _nullWidth(encoding);
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
