import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/app_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  final controller = AppController();
  controller.initialize();
  runApp(ModemZaidApp(controller: controller));
}

class ModemZaidApp extends StatelessWidget {
  final AppController controller;

  const ModemZaidApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final palette = controller.palette;
        return MaterialApp(
          title: 'مودم زيد',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const [
            Locale('ar'),
            Locale('en'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: palette.toThemeData(),
          home: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: controller.isAuthenticated
                ? MainShell(
                    key: const ValueKey('main_shell'),
                    controller: controller,
                  )
                : LoginScreen(
                    key: const ValueKey('login_screen'),
                    controller: controller,
                  ),
          ),
        );
      },
    );
  }
}
