import 'package:flutter/material.dart';

const _seed = Color(0xFF2E5E8C);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),
  );
}

/// Durum renkleri (yoklama / yurt durumu rozetleri)
class StatusColors {
  static const present = Color(0xFF2E7D32);
  static const absent = Color(0xFFC62828);
  static const excused = Color(0xFFEF6C00);
}
