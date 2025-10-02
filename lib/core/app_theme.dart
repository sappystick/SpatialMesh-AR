import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors
  static const _seed = Color(0xFF6750A4);
  static const _errorColor = Color(0xFFBA1A1A);
  static const _neutralVariant = Color(0xFF79747E);
  static const _successColor = Color(0xFF4CAF50);
  static const _warningColor = Color(0xFFFF9800);
  
  // AR-specific colors
  static const arAnchorColor = Color(0xFF00E676);
  static const meshConnectionColor = Color(0xFF2196F3);
  static const earningsColor = Color(0xFFFFD700);
  
  // Gradients
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF6750A4), Color(0xFF7C4DFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const earningsGradient = LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFFF8F00)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  
  static const meshGradient = LinearGradient(
    colors: [Color(0xFF2196F3), Color(0xFF00BCD4)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  
  // Color Schemes
  static final _lightColorScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    error: _errorColor,
    background: Colors.grey[50]!,
  ).copyWith(
    tertiary: _successColor,
    tertiaryContainer: _warningColor,
  );
  
  static final _darkColorScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    error: _errorColor,
    brightness: Brightness.dark,
    background: Color(0xFF1C1B1F),
  ).copyWith(
    tertiary: _successColor,
    tertiaryContainer: _warningColor,
  );
  
  // Typography
  static final _baseTextTheme = GoogleFonts.robotoTextTheme().copyWith(
    displayLarge: GoogleFonts.poppins(
      fontSize: 57,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.25,
    ),
    displayMedium: GoogleFonts.poppins(
      fontSize: 45,
      fontWeight: FontWeight.w400,
    ),
    displaySmall: GoogleFonts.poppins(
      fontSize: 36,
      fontWeight: FontWeight.w400,
    ),
    headlineLarge: GoogleFonts.poppins(
      fontSize: 32,
      fontWeight: FontWeight.w400,
    ),
    headlineMedium: GoogleFonts.poppins(
      fontSize: 28,
      fontWeight: FontWeight.w400,
    ),
    headlineSmall: GoogleFonts.poppins(
      fontSize: 24,
      fontWeight: FontWeight.w400,
    ),
    titleLarge: GoogleFonts.roboto(
      fontSize: 22,
      fontWeight: FontWeight.w400,
    ),
    titleMedium: GoogleFonts.roboto(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15,
    ),
    titleSmall: GoogleFonts.roboto(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
    ),
    bodyLarge: GoogleFonts.roboto(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.5,
    ),
    bodyMedium: GoogleFonts.roboto(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
    ),
    bodySmall: GoogleFonts.roboto(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
    ),
  );
  
  // Light Theme
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: _lightColorScheme,
    brightness: Brightness.light,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    textTheme: _baseTextTheme,
    
    // Component Themes
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 2,
      backgroundColor: _lightColorScheme.surface,
      foregroundColor: _lightColorScheme.onSurface,
      surfaceTintColor: _lightColorScheme.surfaceTint,
    ),
    
    navigationBarTheme: NavigationBarThemeData(
      elevation: 3,
      height: 80,
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      backgroundColor: _lightColorScheme.surface,
      surfaceTintColor: _lightColorScheme.surfaceTint,
      indicatorColor: _lightColorScheme.secondaryContainer,
    ),
    
    cardTheme: CardTheme(
      elevation: 1,
      shape: cardShape,
      clipBehavior: Clip.antiAlias,
      color: _lightColorScheme.surface,
      surfaceTintColor: _lightColorScheme.surfaceTint,
    ),
    
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 1,
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: buttonShape,
      ),
    ),
    
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: buttonShape,
      ),
    ),
    
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    ),
    
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    
    bottomSheetTheme: BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      surfaceTintColor: _lightColorScheme.surfaceTint,
      elevation: 2,
    ),
    
    dialogTheme: DialogTheme(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      surfaceTintColor: _lightColorScheme.surfaceTint,
      elevation: 3,
    ),
  );
  
  // Dark Theme
  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    colorScheme: _darkColorScheme,
    brightness: Brightness.dark,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    textTheme: _baseTextTheme,
    
    // Component Themes - inheriting from light theme where appropriate
    appBarTheme: light.appBarTheme.copyWith(
      backgroundColor: _darkColorScheme.surface,
      foregroundColor: _darkColorScheme.onSurface,
      surfaceTintColor: _darkColorScheme.surfaceTint,
    ),
    
    navigationBarTheme: light.navigationBarTheme.copyWith(
      backgroundColor: _darkColorScheme.surface,
      surfaceTintColor: _darkColorScheme.surfaceTint,
      indicatorColor: _darkColorScheme.secondaryContainer,
    ),
    
    cardTheme: light.cardTheme.copyWith(
      color: _darkColorScheme.surface,
      surfaceTintColor: _darkColorScheme.surfaceTint,
    ),
    
    listTileTheme: light.listTileTheme,
    elevatedButtonTheme: light.elevatedButtonTheme,
    outlinedButtonTheme: light.outlinedButtonTheme,
    textButtonTheme: light.textButtonTheme,
    floatingActionButtonTheme: light.floatingActionButtonTheme,
    snackBarTheme: light.snackBarTheme,
    chipTheme: light.chipTheme,
    
    bottomSheetTheme: light.bottomSheetTheme.copyWith(
      surfaceTintColor: _darkColorScheme.surfaceTint,
    ),
    
    dialogTheme: light.dialogTheme.copyWith(
      surfaceTintColor: _darkColorScheme.surfaceTint,
    ),
  );
  
  // Custom Styles and Constants
  static const cardPadding = EdgeInsets.all(16.0);
  static const listItemPadding = EdgeInsets.symmetric(
    horizontal: 16.0,
    vertical: 12.0,
  );
  static const screenPadding = EdgeInsets.all(16.0);
  
  static final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  
  static final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(20),
  );
  
  static const elevationLow = 1.0;
  static const elevationMedium = 3.0;
  static const elevationHigh = 6.0;
  
  static final shadows = {
    'low': [
      BoxShadow(
        color: Colors.black.withOpacity(0.1),
        blurRadius: 4,
        offset: Offset(0, 2),
      ),
    ],
    'medium': [
      BoxShadow(
        color: Colors.black.withOpacity(0.15),
        blurRadius: 8,
        offset: Offset(0, 4),
      ),
    ],
    'high': [
      BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 12,
        offset: Offset(0, 6),
      ),
    ],
  };
  
  // Animation Durations
  static const animationDurationShort = Duration(milliseconds: 200);
  static const animationDurationMedium = Duration(milliseconds: 300);
  static const animationDurationLong = Duration(milliseconds: 500);
  
  // Animation Curves
  static const animationCurveDefault = Curves.easeInOut;
  static const animationCurveFast = Curves.easeOutCubic;
  static const animationCurveSlow = Curves.easeInOutCubic;
  
  // Screen Breakpoints
  static const breakpointMobile = 600.0;
  static const breakpointTablet = 900.0;
  static const breakpointDesktop = 1200.0;
  
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < breakpointMobile;
  
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= breakpointMobile &&
      MediaQuery.of(context).size.width < breakpointDesktop;
  
  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= breakpointDesktop;
  
  // Chart Colors
  static final chartColorPalette = [
    _seed,
    _seed.withOpacity(0.8),
    _seed.withOpacity(0.6),
    _seed.withOpacity(0.4),
    _neutralVariant,
  ];
}