import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _seed = Color(0xFF5B7CFA);

/// 卡片强调色：按 todo id 稳定取一个，让瀑布流有层次。
const List<Color> _accents = <Color>[
  Color(0xFF6C8CF5),
  Color(0xFF57B98A),
  Color(0xFFE0A34F),
  Color(0xFFE0708C),
  Color(0xFF9A86EF),
  Color(0xFF4FB3B8),
];

Color accentFor(String id) {
  if (id.isEmpty) return _accents.first;
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _accents[hash % _accents.length];
}

Color cardColorFor(BuildContext context, String id) {
  final scheme = Theme.of(context).colorScheme;
  return Color.alphaBlend(
    accentFor(id)
        .withValues(alpha: scheme.brightness == Brightness.dark ? 0.14 : 0.10),
    scheme.surface,
  );
}

/// 已完成卡片：抽掉彩色底，只留一层极淡的中性色，让完成区安静下来。
Color doneCardColorFor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Color.alphaBlend(
    scheme.surfaceContainerHighest.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.30 : 0.50,
    ),
    scheme.surface,
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  final base = ThemeData(colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF6F7FA)
        : const Color(0xFF0F1115),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // AppBar 透明时 Flutter 会按黑色背景推断图标颜色，状态栏会变成白字；
      // 显式跟随主题亮度指定，并保持状态栏透明。
      systemOverlayStyle:
          (brightness == Brightness.light
                  ? SystemUiOverlayStyle.dark
                  : SystemUiOverlayStyle.light)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemStatusBarContrastEnforced: false,
              ),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.7)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
    ),
  );
}
