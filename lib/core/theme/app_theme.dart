import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Modern SaaS product theme — Plus Jakarta Sans, soft shadows, bento cards.
class AppTheme {
  AppTheme._();

  static TextStyle get _base => GoogleFonts.plusJakartaSans();

  // Brand palette — matches React uiThemeSlice defaults (#4f46e5 / #7c3aed)
  static const Color brand = Color(0xFF4F46E5);
  static const Color brandDark = Color(0xFF4338CA);
  static const Color brandLight = Color(0xFFEEF2FF);

  static const Color primary = Color(0xFF111827);
  static const Color accent = Color(0xFF7C3AED);
  static const Color surface = Color(0xFFF8F9FA);
  static const Color card = Colors.white;
  static const Color muted = Color(0xFF6C757D);
  static const Color border = Color(0xFFE9ECEF);
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);
  static const Color orange = Color(0xFFEA580C);

  /// Shared layout scale — keep page / form / list spacing consistent.
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spacePage = 16;
  static const double spaceLg = 20;
  /// Extra space after the last list item. Floating nav is cleared in AppShell.
  static const double spaceNavClearance = 24;

  static const EdgeInsets pagePadding =
      EdgeInsets.fromLTRB(spacePage, spaceMd, spacePage, spaceNavClearance);
  static const EdgeInsets listPadding =
      EdgeInsets.fromLTRB(spacePage, 0, spacePage, spaceNavClearance);
  static const EdgeInsets formPadding =
      EdgeInsets.fromLTRB(spacePage, spacePage, spacePage, spaceNavClearance);
  static const EdgeInsets filterPadding =
      EdgeInsets.fromLTRB(spacePage, spaceMd, spacePage, spaceSm);
  static const EdgeInsets searchPadding =
      EdgeInsets.fromLTRB(spacePage, spaceMd, spacePage, 0);
  static const EdgeInsets chipRowPadding =
      EdgeInsets.fromLTRB(spacePage, spaceSm, spacePage, 10);

  static EdgeInsets sheetPadding(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomSafe = mq.viewInsets.bottom > 0
        ? mq.viewInsets.bottom
        : mq.viewPadding.bottom;
    return EdgeInsets.fromLTRB(
      spacePage,
      spacePage,
      spacePage,
      bottomSafe + spacePage,
    );
  }

  static const List<Color> palette = [
    Color(0xFF4F46E5),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
    Color(0xFFEF4444),
    Color(0xFFEA580C),
    Color(0xFF6366F1),
  ];

  static Color colorAt(int index) => palette[index % palette.length];

  static Color softBg(Color c) => Color.alphaBlend(c.withValues(alpha: 0.1), Colors.white);

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF4F46E5).withValues(alpha: 0.18),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get elevatedShadow => [
        BoxShadow(
          color: const Color(0xFF111827).withValues(alpha: 0.12),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: const Color(0xFF111827).withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  static LinearGradient get brandGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
      );

  static LinearGradient get authGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF4338CA),
          Color(0xFF4F46E5),
          Color(0xFF7C3AED),
          Color(0xFF6366F1),
        ],
        stops: [0.0, 0.35, 0.7, 1.0],
      );

  // Typography scale
  static TextStyle get displaySmall =>
      _base.copyWith(fontSize: 28, fontWeight: FontWeight.w800, color: primary, letterSpacing: -0.5);

  static TextStyle get headlineSmall =>
      _base.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.3);

  static TextStyle get titleMedium =>
      _base.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: primary);

  static TextStyle get titleSmall =>
      _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: primary);

  static TextStyle get labelMedium =>
      _base.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: muted);

  static TextStyle get bodySmall =>
      _base.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: muted);

  static TextTheme get _textTheme => TextTheme(
        displaySmall: displaySmall,
        headlineSmall: headlineSmall,
        titleLarge: titleMedium.copyWith(fontSize: 18),
        titleMedium: titleMedium,
        titleSmall: titleSmall,
        bodyLarge: _base.copyWith(fontSize: 16, color: primary),
        bodyMedium: _base.copyWith(fontSize: 14, color: primary),
        bodySmall: bodySmall,
        labelLarge: _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
        labelMedium: labelMedium,
        labelSmall: _base.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: muted),
      );

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.light,
      primary: brand,
      secondary: accent,
      surface: surface,
      error: danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surface,
      textTheme: _textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: headlineSmall.copyWith(color: Colors.white, fontSize: 18),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: brandLight,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return labelMedium.copyWith(color: brand, fontSize: 11);
          }
          return labelMedium.copyWith(fontSize: 11);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: brand, size: 22);
          }
          return const IconThemeData(color: muted, size: 22);
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: _base.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          elevation: 0,
          shadowColor: brand.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: _base.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          foregroundColor: brand,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          textStyle: _base.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: bodySmall,
        hintStyle: bodySmall.copyWith(color: muted.withValues(alpha: 0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border.withValues(alpha: 0.8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: brand, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: danger, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.08),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        titleTextStyle: titleSmall,
        subtitleTextStyle: bodySmall,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: brandLight,
        selectedColor: brand.withValues(alpha: 0.15),
        labelStyle: labelMedium.copyWith(color: brandDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      dividerTheme: DividerThemeData(color: border.withValues(alpha: 0.7), thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: primary,
        contentTextStyle: _base.copyWith(color: Colors.white, fontSize: 14),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: brand),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: titleMedium,
        contentTextStyle: bodySmall.copyWith(color: primary),
      ),
    );
  }
}

/// Modern pill segment control.
class AppSegmentTabs extends StatelessWidget {
  const AppSegmentTabs({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.colors,
  });

  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  decoration: BoxDecoration(
                    color: index == i
                        ? (colors != null && i < colors!.length ? colors![i] : AppTheme.brand)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: index == i
                        ? [
                            BoxShadow(
                              color: (colors != null && i < colors!.length
                                      ? colors![i]
                                      : AppTheme.brand)
                                  .withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    tabs[i],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.labelMedium.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: index == i ? Colors.white : AppTheme.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tab bar for colored AppBar headers.
class AppBarTabBar extends StatelessWidget implements PreferredSizeWidget {
  const AppBarTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.isScrollable = false,
  });

  final TabController controller;
  final List<Widget> tabs;
  final bool isScrollable;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      isScrollable: isScrollable,
      labelColor: Colors.white,
      unselectedLabelColor: const Color(0xCCFFFFFF),
      labelStyle: AppTheme.labelMedium.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: Colors.white,
      ),
      unselectedLabelStyle: AppTheme.labelMedium.copyWith(fontSize: 13, color: const Color(0xCCFFFFFF)),
      indicatorSize: TabBarIndicatorSize.label,
      indicatorWeight: 3,
      dividerColor: Colors.transparent,
      overlayColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.08)),
      indicator: UnderlineTabIndicator(
        borderSide: const BorderSide(color: Colors.white, width: 3),
        borderRadius: BorderRadius.circular(3),
      ),
      tabs: tabs,
    );
  }
}

/// Soft icon badge — matches React dashboard KPI icon tiles.
class AppIconBadge extends StatelessWidget {
  const AppIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.iconSize = 20,
    this.filled = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withValues(alpha: 0.75)],
          ),
          borderRadius: BorderRadius.circular(size * 0.32),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.28),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.softBg(color),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}
