import 'dart:math';

/// Recovery code generation / validation.
///
/// We use Crockford's base32 alphabet (no I, L, O, or U — chosen to be
/// unambiguous when handwritten on a recovery card) plus a single check
/// character at the end so a mistyped code fails fast instead of hitting
/// the backend and counting toward the per-vault failure budget.
///
/// Format on display: `XXXX-XXXX-XXXX-XXXX` — 16 visible chars + a check
/// char making 17 total, formatted as four groups of four with the check
/// in the last group.
///
/// Wire / storage form: lowercase, no dashes (collation-friendly).
class SharedExpenseRecoveryCode {
  /// Crockford's base32 alphabet (no I, L, O, U).
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Total characters in the code on the wire (including the check char).
  /// Server enforces a 16-character Crockford regex, so the layout is
  /// 15 entropy chars + 1 check = 16 chars. 15 × 5 = 75 bits of entropy.
  static const int wireLength = 16;
  static const int _entropyChars = 15;

  /// Generate a fresh recovery code. Wire form is UPPERCASE Crockford base32
  /// — the backend matches against `/^[0-9A-HJKMNP-TV-Z]{16}$/`. ~75 bits
  /// of entropy; brute-forcing the code space is hopeless.
  static String generate({Random? random}) {
    final rng = random ?? Random.secure();
    final body = StringBuffer();
    for (var i = 0; i < _entropyChars; i++) {
      body.write(_alphabet[rng.nextInt(_alphabet.length)]);
    }
    final check = _checksumChar(body.toString());
    return '$body$check';
  }

  /// Format a code for display: uppercase + dashes every 4 chars.
  static String format(String code) {
    final normalized = _normalize(code);
    final buf = StringBuffer();
    for (var i = 0; i < normalized.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write('-');
      buf.write(normalized[i]);
    }
    return buf.toString();
  }

  /// Returns true if `input` decodes to a syntactically valid code (correct
  /// length AND check char matches). Does NOT prove the code exists in the
  /// vault store — only that it's well-formed.
  static bool isWellFormed(String input) {
    final normalized = _safeNormalize(input);
    if (normalized == null) return false;
    if (normalized.length != wireLength) return false;
    final body = normalized.substring(0, _entropyChars);
    final check = normalized.substring(_entropyChars);
    return _checksumChar(body) == check.toUpperCase();
  }

  /// Normalize user input for transport (UPPERCASE Crockford, no dashes or
  /// spaces). Returns null if any character is outside the alphabet. The
  /// caller should usually call [isWellFormed] first; this is the wire form
  /// once that passes.
  static String? normalizeForWire(String input) {
    final n = _safeNormalize(input);
    if (n == null) return null;
    if (n.length != wireLength) return null;
    return n;
  }

  /// Strip dashes/whitespace and uppercase. Crockford treats I/L as 1 and
  /// O as 0, so we do too — a user reading off paper won't get penalized
  /// for the obvious confusables.
  static String _normalize(String input) {
    final cleaned =
        input.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    final buf = StringBuffer();
    for (final code in cleaned.codeUnits) {
      var c = String.fromCharCode(code);
      if (c == 'I' || c == 'L') c = '1';
      if (c == 'O') c = '0';
      buf.write(c);
    }
    return buf.toString();
  }

  /// [_normalize] but returns null if any character would land outside the
  /// alphabet — keeps [isWellFormed] honest.
  static String? _safeNormalize(String input) {
    final normalized = _normalize(input);
    for (final code in normalized.codeUnits) {
      if (!_alphabet.codeUnits.contains(code)) return null;
    }
    return normalized;
  }

  /// One-character checksum: sum of alphabet positions of the body chars,
  /// mod 32, mapped back through the alphabet. Catches single-char typos
  /// 32/32 of the time and most transpositions.
  static String _checksumChar(String body) {
    var sum = 0;
    for (final code in body.codeUnits) {
      final index = _alphabet.codeUnits.indexOf(code);
      if (index < 0) {
        throw ArgumentError(
            'Body contains non-alphabet character: ${String.fromCharCode(code)}');
      }
      sum += index;
    }
    return _alphabet[sum % _alphabet.length];
  }
}
