import 'package:flutter/material.dart';

@immutable
class CollectionTheme extends ThemeExtension<CollectionTheme> {
  const CollectionTheme({
    required this.backgroundTop,
    required this.backgroundMiddle,
    required this.backgroundBottom,
    required this.panel,
    required this.panelStrong,
    required this.panelBorder,
    required this.glow,
    required this.vinyl,
  });

  final Color backgroundTop;
  final Color backgroundMiddle;
  final Color backgroundBottom;
  final Color panel;
  final Color panelStrong;
  final Color panelBorder;
  final Color glow;
  final Color vinyl;

  @override
  CollectionTheme copyWith({
    Color? backgroundTop,
    Color? backgroundMiddle,
    Color? backgroundBottom,
    Color? panel,
    Color? panelStrong,
    Color? panelBorder,
    Color? glow,
    Color? vinyl,
  }) {
    return CollectionTheme(
      backgroundTop: backgroundTop ?? this.backgroundTop,
      backgroundMiddle: backgroundMiddle ?? this.backgroundMiddle,
      backgroundBottom: backgroundBottom ?? this.backgroundBottom,
      panel: panel ?? this.panel,
      panelStrong: panelStrong ?? this.panelStrong,
      panelBorder: panelBorder ?? this.panelBorder,
      glow: glow ?? this.glow,
      vinyl: vinyl ?? this.vinyl,
    );
  }

  @override
  CollectionTheme lerp(ThemeExtension<CollectionTheme>? other, double t) {
    if (other is! CollectionTheme) {
      return this;
    }
    return CollectionTheme(
      backgroundTop: Color.lerp(backgroundTop, other.backgroundTop, t)!,
      backgroundMiddle: Color.lerp(
        backgroundMiddle,
        other.backgroundMiddle,
        t,
      )!,
      backgroundBottom: Color.lerp(
        backgroundBottom,
        other.backgroundBottom,
        t,
      )!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelStrong: Color.lerp(panelStrong, other.panelStrong, t)!,
      panelBorder: Color.lerp(panelBorder, other.panelBorder, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      vinyl: Color.lerp(vinyl, other.vinyl, t)!,
    );
  }
}

class AppTheme {
  const AppTheme._();

  static const collection = CollectionTheme(
    backgroundTop: Color(0xff071224),
    backgroundMiddle: Color(0xff102f5b),
    backgroundBottom: Color(0xff030711),
    panel: Color(0xd9142442),
    panelStrong: Color(0xf0193156),
    panelBorder: Color(0x6687c8ff),
    glow: Color(0xff45a6ff),
    vinyl: Color(0xff05070b),
  );

  static final ThemeData theme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xff72baff),
      onPrimary: Color(0xff031525),
      primaryContainer: Color(0xff164a80),
      onPrimaryContainer: Color(0xffd9ecff),
      secondary: Color(0xff72e0ff),
      onSecondary: Color(0xff04202b),
      secondaryContainer: Color(0xff16485a),
      onSecondaryContainer: Color(0xffd8f6ff),
      tertiary: Color(0xffb7a6ff),
      onTertiary: Color(0xff1d143b),
      error: Color(0xffff6f7d),
      onError: Color(0xff350006),
      surface: Color(0xff0b1728),
      onSurface: Color(0xffedf5ff),
      surfaceContainerHighest: Color(0xff1a2a40),
      onSurfaceVariant: Color(0xffb8c8d9),
      outline: Color(0xff6f91b8),
      shadow: Color(0xff000000),
    ),
    scaffoldBackgroundColor: collection.backgroundBottom,
    extensions: const [collection],
    cardTheme: CardThemeData(
      color: collection.panel,
      surfaceTintColor: Colors.transparent,
      shadowColor: collection.glow.withValues(alpha: 0.22),
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xff0a1628).withValues(alpha: 0.76),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0x6687c8ff)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xff72baff), width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Color(0xff72baff),
      textColor: Color(0xffedf5ff),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Color(0xff72baff),
      thumbColor: Color(0xff72e0ff),
    ),
  );
}
