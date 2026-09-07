import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'stock_store.dart';

const plum = Color(0xFF372F36),
    linen = Color(0xFFF2ECE5),
    avocado = Color(0xFFC0C26B),
    cement = Color(0xFF8D8C7D),
    maple = Color(0xFFB29762),
    rust = Color(0xFF9F553C);
const paper = Color(0xFFFFFCF8),
    muted = Color(0xFF777268),
    line = Color(0xFFE5DFD6);

ThemeData stockTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: linen,
  colorScheme: ColorScheme.fromSeed(
    seedColor: avocado,
    primary: plum,
    secondary: avocado,
    surface: paper,
    error: rust,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.3,
      color: plum,
    ),
    headlineMedium: TextStyle(
      fontSize: 27,
      fontWeight: FontWeight.w800,
      letterSpacing: -.8,
      color: plum,
    ),
    titleLarge: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w700,
      letterSpacing: -.5,
      color: plum,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: plum,
    ),
    bodyMedium: TextStyle(fontSize: 14, color: plum),
    bodySmall: TextStyle(fontSize: 12, color: muted),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: linen,
    foregroundColor: plum,
    scrolledUnderElevation: 0,
    centerTitle: false,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: paper,
    contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: plum, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: plum,
      foregroundColor: paper,
      minimumSize: const Size(0, 52),
      padding: const EdgeInsets.symmetric(horizontal: 21),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: plum,
      minimumSize: const Size(0, 50),
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  chipTheme: ChipThemeData(
    side: BorderSide.none,
    backgroundColor: paper,
    selectedColor: plum,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  ),
  dividerTheme: const DividerThemeData(color: line, space: 1),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: plum,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
);

// Dark surfaces use the same warm plum family and avocado accents. The light
// theme and its palette above stay unchanged.
const darkLinen = Color(0xFF211D21),
    darkPaper = Color(0xFF2D272D),
    darkMuted = Color(0xFFBBB3A7),
    darkLine = Color(0xFF4D434B);

extension StockPalette on BuildContext {
  bool get isStockDark => Theme.of(this).brightness == Brightness.dark;
  Color get stockPaper => isStockDark ? darkPaper : paper;
  Color get stockLinen => isStockDark ? darkLinen : linen;
  Color get stockInk => isStockDark ? linen : plum;
  Color get stockMuted => isStockDark ? darkMuted : muted;
  Color get stockLine => isStockDark ? darkLine : line;
  Color get stockRust => isStockDark ? const Color(0xFFE99C82) : rust;
  Color get stockPositive => isStockDark ? avocado : const Color(0xFF62643B);
}

ThemeData stockDarkTheme() {
  final light = stockTheme();
  final scheme = ColorScheme.fromSeed(
    brightness: Brightness.dark,
    seedColor: avocado,
    primary: avocado,
    onPrimary: plum,
    secondary: maple,
    onSecondary: plum,
    surface: darkPaper,
    onSurface: linen,
    onSurfaceVariant: darkMuted,
    outline: darkMuted,
    outlineVariant: darkLine,
    error: const Color(0xFFE99C82),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkLinen,
    colorScheme: scheme,
    textTheme: light.textTheme
        .apply(bodyColor: linen, displayColor: linen)
        .copyWith(
          bodySmall: light.textTheme.bodySmall?.copyWith(color: darkMuted),
        ),
    appBarTheme: light.appBarTheme.copyWith(
      backgroundColor: darkLinen,
      foregroundColor: linen,
    ),
    inputDecorationTheme: light.inputDecorationTheme.copyWith(
      fillColor: darkPaper,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: darkLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: darkLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: avocado, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: light.filledButtonTheme.style?.copyWith(
        backgroundColor: const WidgetStatePropertyAll(avocado),
        foregroundColor: const WidgetStatePropertyAll(plum),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: light.outlinedButtonTheme.style?.copyWith(
        foregroundColor: const WidgetStatePropertyAll(linen),
        side: const WidgetStatePropertyAll(BorderSide(color: darkLine)),
      ),
    ),
    chipTheme: light.chipTheme.copyWith(
      backgroundColor: darkPaper,
      selectedColor: plum,
      labelStyle: const TextStyle(color: linen),
    ),
    dividerTheme: light.dividerTheme.copyWith(color: darkLine),
    snackBarTheme: light.snackBarTheme.copyWith(
      contentTextStyle: const TextStyle(color: linen),
    ),
  );
}

class Surface extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  const Surface({
    super.key,
    required this.child,
    this.color = paper,
    this.padding = const EdgeInsets.all(20),
  });
  @override
  Widget build(BuildContext context) {
    final background = color == paper
        ? context.stockPaper
        : color == linen
        ? context.stockLinen
        : color;
    Widget content = child;
    if (context.isStockDark && (color == avocado || color == maple)) {
      content = DefaultTextStyle.merge(
        style: const TextStyle(color: plum),
        child: IconTheme.merge(
          data: const IconThemeData(color: plum),
          child: content,
        ),
      );
    }
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(24),
      child: Padding(padding: padding, child: content),
    );
  }
}

class Eyebrow extends StatelessWidget {
  final String text;
  final Color color;
  const Eyebrow(this.text, {super.key, this.color = muted});
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.8,
      color: color == muted ? context.stockMuted : color,
    ),
  );
}

class Tag extends StatelessWidget {
  final String text;
  final Color color;
  const Tag(this.text, {super.key, this.color = cement});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color == rust
            ? context.stockRust
            : color == const Color(0xFF62643B)
            ? context.stockPositive
            : color,
        fontWeight: FontWeight.w700,
        fontSize: 10,
      ),
    ),
  );
}

IconData categoryIcon(String category) => switch (category.toLowerCase()) {
  'pantry' => Icons.local_cafe_outlined,
  'home' => Icons.coffee_outlined,
  'care' => Icons.spa_outlined,
  'lifestyle' => Icons.shopping_bag_outlined,
  _ => Icons.inventory_2_outlined,
};

class ProductImage extends StatelessWidget {
  final Product product;
  final double size;
  const ProductImage(this.product, {super.key, this.size = 58});

  static Uint8List? decodeBytes(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var cleaned = raw.trim();
    if (cleaned.contains(',')) {
      cleaned = cleaned.substring(cleaned.indexOf(',') + 1);
    }
    try {
      return base64Decode(cleaned);
    } catch (_) {
      try {
        return base64Decode(base64.normalize(cleaned));
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = [avocado, maple, cement, rust];
    final color =
        colors[product.name.codeUnits.fold(0, (a, b) => a + b) % colors.length];
    final bytes = decodeBytes(product.photo);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: size,
        height: size,
        color: color.withValues(alpha: .19),
        child: bytes == null
            ? Icon(
                categoryIcon(product.category),
                color: context.stockInk,
                size: size * .43,
              )
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.stockLinen,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 32, color: cement),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.stockMuted, height: 1.5),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

void showMessage(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
String friendlyError(Object error) => error is StateError
    ? error.message
    : error is FormatException
    ? error.message
    : 'Could not complete this action. Please try again. Your saved data is unchanged.';

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Confirm',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
