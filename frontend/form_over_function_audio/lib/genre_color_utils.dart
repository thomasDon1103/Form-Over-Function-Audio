import 'package:flutter/material.dart';

String genreKey(String genre) => genre.trim().toLowerCase();

Color? genreColorFromHex(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final hex = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  if (hex.length != 6) {
    return null;
  }
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) {
    return null;
  }
  return Color(0xff000000 | parsed);
}

String genreColorToHex(Color color) {
  final value = color.toARGB32() & 0x00ffffff;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color genreColorFor(
  String genre,
  Map<String, String> genreColors,
  Color fallback,
) {
  return genreColorFromHex(genreColors[genreKey(genre)]) ?? fallback;
}
