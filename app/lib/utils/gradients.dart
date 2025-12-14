import 'package:flutter/material.dart';

class GradientUtils {
  static const Map<int, List<Color>> gradientColors = {
    1: [Color(0xFF1b0b2e), Color(0xFF3a0f5c)], // CBE: Dark Purple (from web)
    2: [Color(0xFFd97706), Color(0xFF1a3a5c)], // Awash: Orange / Blue
    3: [Color(0xFFd9b90b), Color(0xFF382e0c)], // Boa: Dark Yellow
    4: [Color(0xFF1a2d5c), Color(0xFF344e7b)], // Dashen: Dark Blue
    6: [Color.fromARGB(255, 29, 56, 229), Color.fromARGB(255, 144, 213, 238)], // Telebirr: White to Light Green
    99: [
      Color(0xFF2563EB),
      Color(0xFF1E3A8A)
    ], // Totals: Blue (Vibrant to Dark)
  };

  static const List<Color> defaultColors = [
    Color(0xFF1b0b2e),
    Color(0xFF3a0f5c)
  ];

  /// Returns a LinearGradient based on the bank ID.
  /// Simulates 135deg (TopLeft to BottomRight)
  static LinearGradient getGradient(int id) {
    final colors = gradientColors[id] ?? defaultColors;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );
  }
}
