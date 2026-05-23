import 'package:flutter/material.dart';

import 'package:multiview_desktop/multiview_desktop.dart';
import 'pages/home.dart';
import 'utils/theme_config.dart';

void main() => runMultiApp(const MainWindowRoot(),
    config: MultiAppConfig(closeMode: CloseMode.cascade)
);

// ---------------------------------------------------------------------------
// Root widget for the main window
// ---------------------------------------------------------------------------

/// Root widget for the initial (main) OS window.
///
/// Every secondary window opened via [addWindow] uses [_SecondaryWindowRoot]
/// which is defined inside pages/home.dart and shares the same [themeConfig]
/// singleton.
class MainWindowRoot extends StatefulWidget {
  const MainWindowRoot({super.key});

  @override
  State<MainWindowRoot> createState() => _MainWindowRootState();
}

class _MainWindowRootState extends State<MainWindowRoot> {
  @override
  void initState() {
    super.initState();
    themeConfig.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeConfig.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: themeConfig.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
