import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';

class LuminhawTheme {
  LuminhawTheme._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.green),
    fontFamily: 'Poppins',
  );
}
