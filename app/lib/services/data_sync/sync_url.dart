import 'package:flutter/foundation.dart';

/// Validation for user-entered destination URLs. Guards against foot-guns and
/// accidental LAN/loopback targeting (a light SSRF-style guard — lower stakes
/// here since requests run on the user's own device, but it prevents pointing
/// the app at routers/internal services by mistake).
class SyncUrl {
  /// Returns null when [value] is an acceptable destination base URL, otherwise
  /// a human-readable error message (suitable as a form validator result).
  static String? validate(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Required';

    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a full URL, e.g. https://api.example.com';
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return 'Only http(s) URLs are supported';
    }
    if (scheme == 'http' && !kDebugMode) {
      return 'Use https:// so your data is encrypted in transit';
    }
    if (_isBlockedHost(uri.host)) {
      return 'Local and private network addresses are not allowed';
    }
    return null;
  }

  static bool _isBlockedHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.localhost')) {
      return true;
    }
    if (h == '::1' || h.startsWith('fe80:') || h.startsWith('fc') || h.startsWith('fd')) {
      return true;
    }

    final parts = h.split('.');
    if (parts.length == 4 && parts.every((p) => int.tryParse(p) != null)) {
      final octets = parts.map(int.parse).toList();
      final a = octets[0], b = octets[1];
      if (a == 127) return true; // loopback
      if (a == 10) return true; // private
      if (a == 192 && b == 168) return true; // private
      if (a == 172 && b >= 16 && b <= 31) return true; // private
      if (a == 169 && b == 254) return true; // link-local
      if (a == 0) return true;
    }
    return false;
  }
}
