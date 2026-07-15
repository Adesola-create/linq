import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────
// LINQ Brand Tokens v1.0
// Source of truth: LINQ Brand Guidelines v1.0
// ─────────────────────────────────────────────────────────────────

class LinqColors {
  LinqColors._();

  // ── Forest (primary brand) ──────────────────────────────────────
  static const forest50 = Color(0xFFF2F6F4);
  static const forest100 = Color(0xFFDCE8E3);
  static const forest200 = Color(0xFFB3CDC2);
  static const forest300 = Color(0xFF7FA89A);
  static const forest400 = Color(0xFF4D7F73);
  static const forest500 = Color(0xFF1F4E48); // primary brand
  static const forest600 = Color(0xFF19403B); // hover
  static const forest700 = Color(0xFF133230); // active/pressed
  static const forest800 = Color(0xFF0E2624);
  static const forest900 = Color(0xFF081715);

  // ── Cream (secondary brand) ─────────────────────────────────────
  static const cream50 = Color(0xFFFAFAF7);
  static const cream100 = Color(0xFFF5F2E9);
  static const cream200 = Color(0xFFF0EAD2); // hero/marketing canvas
  static const cream300 = Color(0xFFE8E0BD);
  static const cream400 = Color(0xFFD9CC9D);
  static const cream500 = Color(0xFFC2B477);

  // ── Brass (verification accent — trust signals ONLY) ────────────
  static const brass50 = Color(0xFFFBF6E8);
  static const brass100 = Color(0xFFF4E9C2);
  static const brass200 = Color(0xFFE8D588);
  static const brass300 = Color(0xFFD4B85C);
  static const brass500 = Color(0xFFB89834); // verified primary
  static const brass600 = Color(0xFF9A7E26);
  static const brass700 = Color(0xFF7C641C);
  static const brass800 = Color(0xFF5C4915);

  // ── Stone (neutrals — warm, never cool grey) ────────────────────
  static const stone0 = Color(0xFFFFFFFF);
  static const stone50 = Color(0xFFFAFAF8);
  static const stone100 = Color(0xFFF4F2EC);
  static const stone200 = Color(0xFFE8E5DA); // default border
  static const stone300 = Color(0xFFD4D0C0); // strong border
  static const stone400 = Color(0xFFA8A493); // tertiary / placeholder
  static const stone500 = Color(0xFF7C7868); // secondary text / icons
  static const stone600 = Color(0xFF5C5849); // default body text
  static const stone700 = Color(0xFF403D32); // strong body / headlines
  static const stone800 = Color(0xFF2A281F); // max-emphasis headlines
  static const stone900 = Color(0xFF1A1814);

  // ── Semantic: Success (Sage) ─────────────────────────────────────
  static const success50 = Color(0xFFEEF5EC);
  static const success100 = Color(0xFFD5E8CF);
  static const success500 = Color(0xFF3D7B3A);
  static const success700 = Color(0xFF2A5728);

  // ── Semantic: Warning (Ochre) ────────────────────────────────────
  static const warning50 = Color(0xFFFAF1DD);
  static const warning100 = Color(0xFFF4E0AF);
  static const warning500 = Color(0xFFC8881C);
  static const warning700 = Color(0xFF8B5C12);

  // ── Semantic: Danger (Clay) ──────────────────────────────────────
  static const danger50 = Color(0xFFF8E9E5);
  static const danger100 = Color(0xFFF0CFC5);
  static const danger500 = Color(0xFFB83C28);
  static const danger700 = Color(0xFF7E2917);

  // ── Semantic: Info (Slate-blue) ──────────────────────────────────
  static const info50 = Color(0xFFE8EEF3);
  static const info500 = Color(0xFF3F6A8C);
  static const info700 = Color(0xFF274359);

  // ── Semantic aliases ─────────────────────────────────────────────
  static const bgPage = cream50; // provider workspace
  static const bgPageApp = stone50; // customer / money surfaces
  static const bgSurface = stone0;
  static const bgSurfaceAlt = stone50;
  static const bgHover = stone100;

  static const textPrimary = stone800;
  static const textBody = stone600;
  static const textSecondary = stone500;
  static const textTertiary = stone400;
  static const textOnBrand = stone0;

  static const borderDefault = stone200;
  static const borderStrong = stone300;

  static const brandPrimary = forest500;
  static const brandHover = forest600;
  static const brandActive = forest700;

  static const trust = brass500;
  static const trustBg = brass50;
  static const trustText = brass700;
}

class LinqRadius {
  LinqRadius._();
  static const none = Radius.circular(0);
  static const xs = Radius.circular(2);
  static const sm = Radius.circular(4);
  static const md = Radius.circular(8); // buttons, inputs, small cards
  static const lg = Radius.circular(12); // cards, panels, modals
  static const xl = Radius.circular(16); // large cards
  static const x2l = Radius.circular(20); // marketing / onboarding
  static const full = Radius.circular(9999);

  // BorderRadius helpers
  static final borderNone = BorderRadius.zero;
  static final borderXs = BorderRadius.circular(2);
  static final borderSm = BorderRadius.circular(4);
  static final borderMd = BorderRadius.circular(8);
  static final borderLg = BorderRadius.circular(12);
  static final borderXl = BorderRadius.circular(16);
  static final borderX2l = BorderRadius.circular(20);
  static final borderFull = BorderRadius.circular(9999);
}

class LinqShadows {
  LinqShadows._();
  // Shadow color: stone/800 at varying opacity (not pure black)
  static const _c = Color(0x0A2A281F); // base — overridden per token

  static const none = <BoxShadow>[];

  static const xs = [
    BoxShadow(color: Color(0x0A2A281F), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const sm = [
    BoxShadow(color: Color(0x0F2A281F), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A2A281F), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const md = [
    BoxShadow(
      color: Color(0x142A281F),
      blurRadius: 8,
      spreadRadius: -2,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x0A2A281F),
      blurRadius: 4,
      spreadRadius: -1,
      offset: Offset(0, 2),
    ),
  ];

  static const lg = [
    BoxShadow(
      color: Color(0x1A2A281F),
      blurRadius: 24,
      spreadRadius: -6,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x0A2A281F),
      blurRadius: 8,
      spreadRadius: -2,
      offset: Offset(0, 4),
    ),
  ];

  static const xl = [
    BoxShadow(
      color: Color(0x242A281F),
      blurRadius: 48,
      spreadRadius: -12,
      offset: Offset(0, 24),
    ),
    BoxShadow(
      color: Color(0x0F2A281F),
      blurRadius: 16,
      spreadRadius: -4,
      offset: Offset(0, 8),
    ),
  ];
}

class LinqSpacing {
  LinqSpacing._();
  static const s0 = 0.0;
  static const s0_5 = 2.0;
  static const s1 = 4.0;
  static const s1_5 = 6.0;
  static const s2 = 8.0;
  static const s2_5 = 10.0;
  static const s3 = 12.0;
  static const s4 = 16.0; // default card padding
  static const s5 = 20.0;
  static const s6 = 24.0; // section gap / raised card padding
  static const s8 = 32.0;
  static const s10 = 40.0; // touch target minimum
  static const s12 = 48.0;
  static const s16 = 64.0;
  static const s20 = 80.0;
  static const s24 = 96.0;
}

class LinqFonts {
  LinqFonts._();

  static TextStyle plusJakarta({
    double? fontSize,
    FontWeight weight = FontWeight.w600,
    double? letterSpacing,
    double? height,
    Color? color,
  }) => GoogleFonts.plusJakartaSans(
    fontSize: fontSize,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle inter({
    double? fontSize,
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    double? height,
    Color? color,
  }) => GoogleFonts.inter(
    fontSize: fontSize,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle jetbrainsMono({
    double? fontSize,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: fontSize,
    fontWeight: weight,
    color: color,
  );
}

class LinqTextStyles {
  LinqTextStyles._();

  // Display — Plus Jakarta Sans
  static TextStyle get display2xl => LinqFonts.plusJakarta(
    fontSize: 48,
    weight: FontWeight.w700,
    letterSpacing: -1.20,
    height: 1.05,
    color: LinqColors.textPrimary,
  );
  static TextStyle get displayXl => LinqFonts.plusJakarta(
    fontSize: 40,
    weight: FontWeight.w700,
    letterSpacing: -0.88,
    height: 1.10,
    color: LinqColors.textPrimary,
  );
  static TextStyle get displayLg => LinqFonts.plusJakarta(
    fontSize: 32,
    weight: FontWeight.w600,
    letterSpacing: -0.64,
    height: 1.15,
    color: LinqColors.textPrimary,
  );
  static TextStyle get h1 => LinqFonts.plusJakarta(
    fontSize: 28,
    weight: FontWeight.w600,
    letterSpacing: -0.50,
    height: 1.20,
    color: LinqColors.textPrimary,
  );
  static TextStyle get h2 => LinqFonts.plusJakarta(
    fontSize: 22,
    weight: FontWeight.w600,
    letterSpacing: -0.31,
    height: 1.25,
    color: LinqColors.textPrimary,
  );
  static TextStyle get h3 => LinqFonts.plusJakarta(
    fontSize: 18,
    weight: FontWeight.w600,
    letterSpacing: -0.20,
    height: 1.35,
    color: LinqColors.textPrimary,
  );
  static TextStyle get h4 => LinqFonts.inter(
    fontSize: 16,
    weight: FontWeight.w600,
    letterSpacing: -0.08,
    height: 1.40,
    color: LinqColors.textPrimary,
  );

  // Body — Inter
  static TextStyle get bodyLg =>
      LinqFonts.inter(fontSize: 17, height: 1.60, color: LinqColors.textBody);
  static TextStyle get body =>
      LinqFonts.inter(fontSize: 15, height: 1.55, color: LinqColors.textBody);
  static TextStyle get bodySm => LinqFonts.inter(
    fontSize: 13,
    letterSpacing: 0.065,
    height: 1.50,
    color: LinqColors.textSecondary,
  );
  static TextStyle get bodyXs => LinqFonts.inter(
    fontSize: 11,
    weight: FontWeight.w500,
    letterSpacing: 0.22,
    height: 1.45,
    color: LinqColors.textTertiary,
  );

  // Labels
  static TextStyle get label => LinqFonts.inter(
    fontSize: 13,
    weight: FontWeight.w500,
    letterSpacing: 0.13,
    height: 1.40,
    color: LinqColors.textBody,
  );
  static TextStyle get labelSm => LinqFonts.inter(
    fontSize: 11,
    weight: FontWeight.w600,
    letterSpacing: 0.66,
    height: 1.30,
    color: LinqColors.textSecondary,
  );

  // Mono — JetBrains Mono
  static TextStyle get code =>
      LinqFonts.jetbrainsMono(fontSize: 13, color: LinqColors.textBody);
  static TextStyle get codeSm =>
      LinqFonts.jetbrainsMono(fontSize: 11, color: LinqColors.textSecondary);

  // Money / trust scores — Plus Jakarta Sans 600, tabular numerals
  static TextStyle moneyStyle({double fontSize = 28, Color? color}) =>
      LinqFonts.plusJakarta(
        fontSize: fontSize,
        weight: FontWeight.w600,
        color: color ?? LinqColors.textPrimary,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

class LinqBorders {
  LinqBorders._();
  static const hairline = 0.5;
  static const thin = 1.0; // default
  static const medium = 1.5; // focus rings, active states
  static const thick = 2.0; // selected / featured cards
}

class LinqDurations {
  LinqDurations._();
  static const instant = Duration(milliseconds: 50);
  static const fast = Duration(milliseconds: 150); // default
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const slower = Duration(milliseconds: 600);
}

class LinqCurves {
  LinqCurves._();
  static const standard = Cubic(0.2, 0.0, 0.2, 1.0); // default
  static const emphatic = Cubic(0.4, 0.0, 0.2, 1.0); // page transitions
  static const decelerate = Cubic(0.0, 0.0, 0.2, 1.0); // arriving
  static const accelerate = Cubic(0.4, 0.0, 1.0, 1.0); // leaving
}

// ── ThemeData factory ────────────────────────────────────────────
ThemeData linqTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: LinqColors.bgPageApp,
    colorScheme: base.colorScheme.copyWith(
      primary: LinqColors.forest500,
      onPrimary: LinqColors.textOnBrand,
      secondary: LinqColors.brass500,
      onSecondary: LinqColors.stone0,
      surface: LinqColors.bgSurface,
      onSurface: LinqColors.textPrimary,
      error: LinqColors.danger500,
      onError: LinqColors.stone0,
      outline: LinqColors.borderDefault,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
      bodyLarge: LinqTextStyles.body,
      bodyMedium: LinqTextStyles.body,
      bodySmall: LinqTextStyles.bodySm,
      labelLarge: LinqTextStyles.label,
      labelSmall: LinqTextStyles.labelSm,
      titleLarge: LinqTextStyles.h2,
      titleMedium: LinqTextStyles.h3,
      titleSmall: LinqTextStyles.h4,
      headlineLarge: LinqTextStyles.displayLg,
      headlineMedium: LinqTextStyles.h1,
      headlineSmall: LinqTextStyles.h2,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: LinqColors.bgSurface,
      foregroundColor: LinqColors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: LinqTextStyles.h3,
      systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    ),
    cardTheme: CardThemeData(
      color: LinqColors.bgSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: LinqRadius.borderLg,
        side: const BorderSide(
          color: LinqColors.borderDefault,
          width: LinqBorders.thin,
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: linqPrimaryButton()),
    outlinedButtonTheme: OutlinedButtonThemeData(style: linqOutlinedButton()),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LinqColors.stone100,
      border: OutlineInputBorder(
        borderRadius: LinqRadius.borderMd,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: LinqRadius.borderMd,
        borderSide: const BorderSide(
          color: LinqColors.borderDefault,
          width: LinqBorders.thin,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: LinqRadius.borderMd,
        borderSide: const BorderSide(
          color: LinqColors.forest500,
          width: LinqBorders.medium,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: LinqRadius.borderMd,
        borderSide: const BorderSide(
          color: LinqColors.danger500,
          width: LinqBorders.thin,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: LinqRadius.borderMd,
        borderSide: const BorderSide(
          color: LinqColors.danger500,
          width: LinqBorders.medium,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LinqSpacing.s4,
        vertical: LinqSpacing.s3,
      ),
      labelStyle: LinqTextStyles.label.copyWith(color: LinqColors.forest500),
      hintStyle: LinqTextStyles.body.copyWith(color: LinqColors.textTertiary),
      helperStyle: LinqTextStyles.bodyXs.copyWith(
        color: LinqColors.textTertiary,
      ),
      errorStyle: LinqTextStyles.bodyXs.copyWith(color: LinqColors.danger500),
    ),
    dividerTheme: const DividerThemeData(
      color: LinqColors.borderDefault,
      thickness: LinqBorders.thin,
      space: 0,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: LinqColors.stone100,
      labelStyle: LinqTextStyles.labelSm,
      side: const BorderSide(
        color: LinqColors.borderDefault,
        width: LinqBorders.thin,
      ),
      shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderSm),
      padding: const EdgeInsets.symmetric(
        horizontal: LinqSpacing.s2_5,
        vertical: LinqSpacing.s1,
      ),
    ),
  );
}

// ── Shared input decoration factory ─────────────────────────────
InputDecoration linqInputDecoration({
  required String label,
  IconData? icon,
  Widget? prefix,
  Widget? suffix,
  String? helper,
}) {
  return InputDecoration(
    labelText: label,
    helperText: helper,
    helperStyle: LinqTextStyles.bodyXs.copyWith(color: LinqColors.textTertiary),
    labelStyle: LinqTextStyles.label.copyWith(color: LinqColors.forest500),
    prefixIcon: icon != null ? Icon(icon, color: LinqColors.forest500, size: 20) : null,
    prefix: prefix,
    suffixIcon: suffix,
    filled: true,
    fillColor: LinqColors.stone100,
    border: OutlineInputBorder(
      borderRadius: LinqRadius.borderMd,
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: LinqRadius.borderMd,
      borderSide: const BorderSide(
        color: LinqColors.borderDefault,
        width: LinqBorders.thin,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: LinqRadius.borderMd,
      borderSide: const BorderSide(
        color: LinqColors.forest500,
        width: LinqBorders.medium,
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: LinqRadius.borderMd,
      borderSide: const BorderSide(
        color: LinqColors.danger500,
        width: LinqBorders.thin,
      ),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: LinqRadius.borderMd,
      borderSide: const BorderSide(
        color: LinqColors.danger500,
        width: LinqBorders.medium,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: LinqSpacing.s4,
      vertical: LinqSpacing.s3,
    ),
  );
}

// ── Primary button style ─────────────────────────────────────────
ButtonStyle linqPrimaryButton({double verticalPadding = LinqSpacing.s3}) {
  return ElevatedButton.styleFrom(
    backgroundColor: LinqColors.forest500,
    foregroundColor: LinqColors.textOnBrand,
    minimumSize: const Size(double.infinity, LinqSpacing.s10),
    padding: EdgeInsets.symmetric(vertical: verticalPadding),
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
    textStyle: LinqTextStyles.label.copyWith(fontWeight: FontWeight.w600),
  );
}

// ── Outlined button style ────────────────────────────────────────
ButtonStyle linqOutlinedButton() {
  return OutlinedButton.styleFrom(
    foregroundColor: LinqColors.forest500,
    minimumSize: const Size(double.infinity, LinqSpacing.s10),
    side: const BorderSide(
      color: LinqColors.forest500,
      width: LinqBorders.thin,
    ),
    shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
    textStyle: LinqTextStyles.label.copyWith(fontWeight: FontWeight.w600),
  );
}

// ── Verified badge ───────────────────────────────────────────────
Widget linqVerifiedBadge() {
  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: LinqSpacing.s2_5,
      vertical: LinqSpacing.s1,
    ),
    decoration: BoxDecoration(
      color: LinqColors.trustBg,
      borderRadius: LinqRadius.borderFull,
      border: Border.all(color: LinqColors.brass200),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.verified_user, color: LinqColors.trust, size: 12),
        SizedBox(width: 4),
        Text(
          'LINQ VERIFIED',
          style: TextStyle(
            color: LinqColors.trustText,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}

Widget linqAvatar({
  required double radius,
  String? imageUrl,
  Color backgroundColor = LinqColors.stone100,
  IconData fallbackIcon = Icons.person,
}) {
  final url = imageUrl?.trim();
  if (url == null || url.isEmpty) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Icon(
        fallbackIcon,
        color: LinqColors.textOnBrand,
        size: radius * 0.9,
      ),
    );
  }

  // Validate URL format to prevent exceptions
  try {
    final uri = Uri.parse(url);
    if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) {
      // Invalid URL format, show fallback
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: Icon(
          fallbackIcon,
          color: LinqColors.textOnBrand,
          size: radius * 0.9,
        ),
      );
    }
  } catch (e) {
    // URL parsing failed, show fallback
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Icon(
        fallbackIcon,
        color: LinqColors.textOnBrand,
        size: radius * 0.9,
      ),
    );
  }

  return Container(
    width: radius * 2,
    height: radius * 2,
    decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
    child: ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        httpHeaders: const {'User-Agent': 'LINQ-App/1.0'},
        errorListener: (_) {
          CachedNetworkImage.evictFromCache(url);
        },
        placeholder: (_, __) => Container(color: backgroundColor),
        errorWidget: (_, __, ___) => Container(
          color: backgroundColor,
          child: Icon(
            fallbackIcon,
            color: LinqColors.textOnBrand,
            size: radius * 0.9,
          ),
        ),
      ),
    ),
  );
}
