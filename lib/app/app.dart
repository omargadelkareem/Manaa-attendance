import 'package:flutter/material.dart';

import '../features/splash/presentation/splash_screen.dart';
import 'theme/app_theme.dart';

class ManaaApp extends StatelessWidget {
  const ManaaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مناع للزجاج',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: const SplashScreen(),
    );
  }
}
