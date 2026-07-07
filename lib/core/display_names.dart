/// Friendly display names for missing metadata.
///
/// MediaStore reports unknown artist/album as the literal string `<unknown>`
/// (and the scanner stores whatever it gets), so this is the ONE place that
/// turns `<unknown>` / null / empty into a human label. Use it everywhere a
/// name is shown (see CLAUDE.md conventions) — never format these inline.
extension DisplayNames on String? {
  bool get _isMissing {
    final String? v = this?.trim();
    return v == null || v.isEmpty || v.toLowerCase() == '<unknown>';
  }

  String get artistOrUnknown => _isMissing ? 'Unknown artist' : this!;

  String get albumOrUnknown => _isMissing ? 'Unknown album' : this!;
}
