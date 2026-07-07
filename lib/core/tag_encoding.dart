/// Legacy tag-encoding repair for mojibake metadata.
///
/// Many Arabic (and other legacy-codepage) MP3s carry ID3v1 / ID3v2.3 text
/// frames whose bytes are Windows-1256 but whose declared encoding is Latin-1
/// (ISO-8859-1). MediaStore decodes them as Latin-1, so a title that should read
/// "أغنية" comes back as a run of Latin-1 accented punctuation — or, when the
/// pipeline lost bytes, as `?` / U+FFFD replacement characters.
///
/// This module is pure (no I/O, no plugins) so the whole heuristic is unit
/// testable against fixture bytes:
///  * [decodeCp1256] maps raw bytes through the Windows-1256 table.
///  * [reinterpretLatin1AsCp1256] takes an already-(mis)decoded Latin-1 string,
///    recovers its bytes, and re-decodes them as CP1256.
///  * [looksSuspicious] is the cheap pre-filter (skip clean ASCII titles).
///  * [bestDecoding] scores the original against the CP1256 re-decode and
///    returns whichever reads as "more Arabic, no more garbage".
library;

/// Unicode replacement character — the marker of a lossy decode.
const int _kReplacement = 0xFFFD;

/// Windows-1256 (CP1256) high half: code points for bytes 0x80..0xFF. Bytes
/// 0x00..0x7F are ASCII identity and not tabulated. This is the canonical
/// Microsoft mapping (unmapped slots fall back to the byte value, but CP1256
/// has none in this range).
const List<int> _kCp1256High = <int>[
  0x20AC, 0x067E, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, // 80-87
  0x02C6, 0x2030, 0x0679, 0x2039, 0x0152, 0x0686, 0x0698, 0x0688, // 88-8F
  0x06AF, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, // 90-97
  0x06A9, 0x2122, 0x0691, 0x203A, 0x0153, 0x200C, 0x200D, 0x06BA, // 98-9F
  0x00A0, 0x060C, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7, // A0-A7
  0x00A8, 0x00A9, 0x06BE, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF, // A8-AF
  0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7, // B0-B7
  0x00B8, 0x00B9, 0x061B, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x061F, // B8-BF
  0x06C1, 0x0621, 0x0622, 0x0623, 0x0624, 0x0625, 0x0626, 0x0627, // C0-C7
  0x0628, 0x0629, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x062F, // C8-CF
  0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x0636, 0x00D7, // D0-D7
  0x0637, 0x0638, 0x0639, 0x063A, 0x0640, 0x0641, 0x0642, 0x0643, // D8-DF
  0x00E0, 0x0644, 0x00E2, 0x0645, 0x0646, 0x0647, 0x0648, 0x00E7, // E0-E7
  0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x0649, 0x064A, 0x00EE, 0x00EF, // E8-EF
  0x064B, 0x064C, 0x064D, 0x064E, 0x00F4, 0x064F, 0x0650, 0x00F7, // F0-F7
  0x0651, 0x00F9, 0x0652, 0x00FB, 0x00FC, 0x200E, 0x200F, 0x06D2, // F8-FF
];

/// Decodes raw [bytes] as Windows-1256 (CP1256) text.
String decodeCp1256(List<int> bytes) {
  final StringBuffer out = StringBuffer();
  for (final int b in bytes) {
    final int byte = b & 0xFF;
    out.writeCharCode(byte < 0x80 ? byte : _kCp1256High[byte - 0x80]);
  }
  return out.toString();
}

/// Whether every code unit of [s] fits in a single byte (i.e. [s] could be the
/// result of a Latin-1 decode, so its bytes are recoverable losslessly).
bool _isPureLatin1(String s) {
  for (final int u in s.codeUnits) {
    if (u > 0xFF) return false;
  }
  return true;
}

/// Reinterprets a Latin-1-decoded [s] as CP1256: recovers the underlying bytes
/// (each code unit is one byte) and decodes them through the CP1256 table.
/// Returns null when [s] isn't pure Latin-1 (so nothing to reinterpret).
String? reinterpretLatin1AsCp1256(String s) {
  if (!_isPureLatin1(s)) return null;
  return decodeCp1256(s.codeUnits);
}

/// True for Arabic-block code points (incl. supplement + presentation forms).
bool _isArabic(int c) =>
    (c >= 0x0600 && c <= 0x06FF) ||
    (c >= 0x0750 && c <= 0x077F) ||
    (c >= 0xFB50 && c <= 0xFDFF) ||
    (c >= 0xFE70 && c <= 0xFEFF);

/// A "letter-like Latin-1 high" code unit — the accented-punctuation soup a
/// misdecoded CP1256 Arabic string turns into (0xA0..0xFF, excluding the plain
/// ASCII range). Used as a mojibake signal.
bool _isLatin1High(int c) => c >= 0x00A0 && c <= 0x00FF;

/// Cheap pre-filter: does [s] look like it *might* be mojibake and thus worth
/// running [bestDecoding] over? True when it carries replacement chars, a run of
/// literal `?`, or two-plus Latin-1 high chars (the misdecode fingerprint).
/// Clean ASCII / already-correct UTF-8 returns false, so a full-library sweep
/// only pays the scoring cost on the handful of suspect rows.
bool looksSuspicious(String s) {
  if (s.isEmpty) return false;
  int high = 0;
  int replacement = 0;
  int question = 0;
  for (final int c in s.runes) {
    if (c == _kReplacement) {
      replacement++;
    } else if (c == 0x3F) {
      question++;
    } else if (_isLatin1High(c)) {
      high++;
    }
  }
  if (replacement > 0) return true;
  if (high >= 2) return true;
  // A run of >= 2 consecutive '?' with no real letters is a classic lossy tag.
  if (question >= 2 && question >= s.runes.length - question) return true;
  return false;
}

/// Score a string for "reads as real text": Arabic letters are the win we're
/// chasing; replacement/garbage chars are the penalty.
int _score(String s) {
  int arabic = 0;
  int garbage = 0;
  for (final int c in s.runes) {
    if (_isArabic(c)) {
      arabic++;
    } else if (c == _kReplacement || _isLatin1High(c)) {
      garbage++;
    }
  }
  return arabic * 2 - garbage;
}

/// Returns the best reading of a possibly-mojibake [original]: either the string
/// unchanged, or its CP1256 reinterpretation — whichever scores higher. A proper
/// UTF-8 title (Arabic code points already > 0xFF, or plain ASCII) is returned
/// untouched, because it isn't pure Latin-1 (or has nothing to gain). Never
/// returns null; callers compare against [original] to detect a repair.
///
/// Self-guarded by [looksSuspicious]: a name that doesn't look like mojibake is
/// returned as-is, so an ordinary accented Latin title (e.g. "Björk", whose `ö`
/// would otherwise map to a CP1256 diacritic) is never mangled — even when this
/// is called outside the repair sweep.
String bestDecoding(String original) {
  if (!looksSuspicious(original)) return original;
  final String? candidate = reinterpretLatin1AsCp1256(original);
  if (candidate == null || candidate == original) return original;
  // Only prefer the re-decode when it genuinely surfaces Arabic and doesn't add
  // replacement chars — guards ASCII-with-a-stray-accent from being mangled.
  final int originalScore = _score(original);
  final int candidateScore = _score(candidate);
  final bool candidateHasArabic = candidate.runes.any(_isArabic);
  if (candidateHasArabic && candidateScore > originalScore) return candidate;
  return original;
}
