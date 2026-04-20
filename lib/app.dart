import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:unique_ding_kitchen/l10n/app_localizations.dart';
import 'package:unique_ding_kitchen/services/menu_repository.dart';
import 'package:unique_ding_kitchen/views/ordering_view.dart';

class HomeDiningApp extends StatefulWidget {
  HomeDiningApp({
    super.key,
    MenuRepository? repository,
    this.siteName = "UniqueDing's Kitchen",
    this.menuSource = 'local',
    this.trilliumUrl = '',
    this.trilliumTitle = '',
  }) : repository =
           repository ??
           AssetMenuRepository(
             menuSource: menuSource,
             trilliumUrl: trilliumUrl,
             trilliumTitle: trilliumTitle,
           );

  final MenuRepository repository;
  final String siteName;
  final String menuSource;
  final String trilliumUrl;
  final String trilliumTitle;

  @override
  State<HomeDiningApp> createState() => _HomeDiningAppState();
}

class _HomeDiningAppState extends State<HomeDiningApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('zh');

  void _setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  void _setLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    const clay = Color(0xFFB65E48);
    const tea = Color(0xFF708A6E);
    const cream = Color(0xFFF8F1E7);
    final baseTheme = ThemeData(useMaterial3: true);
    final baseTextTheme = baseTheme.textTheme;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: widget.siteName,
      locale: _locale,
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
        Locale('ja'),
        Locale('ko'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: cream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: clay,
          primary: clay,
          secondary: tea,
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        fontFamilyFallback: const <String>[
          'Noto Sans CJK Local',
          'PingFang SC',
          'PingFang HK',
          'PingFang TC',
          'Hiragino Sans GB',
          'Hiragino Sans CNS',
          'Noto Sans CJK SC',
          'Noto Sans CJK TC',
          'Noto Sans CJK KR',
          'Noto Sans SC',
          'Noto Sans TC',
          'Noto Sans HK',
          'Noto Sans KR',
          'Source Han Sans SC',
          'Source Han Sans TC',
          'Source Han Sans KR',
          'Apple SD Gothic Neo',
          'Malgun Gothic',
          'Meiryo',
          'Microsoft YaHei',
          'WenQuanYi Micro Hei',
          'Arial Unicode MS',
          'sans-serif',
        ],
        textTheme: baseTextTheme.copyWith(
          headlineLarge: baseTextTheme.headlineLarge?.copyWith(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2C1D18),
          ),
          headlineMedium: baseTextTheme.headlineMedium?.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2C1D18),
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2C1D18),
          ),
          bodyLarge: baseTextTheme.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.55,
            color: const Color(0xFF4D3A33),
          ),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.45,
            color: const Color(0xFF6C564C),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1C1714),
        colorScheme: ColorScheme.fromSeed(
          seedColor: clay,
          primary: const Color(0xFFD18B75),
          secondary: const Color(0xFF9AC19A),
          surface: const Color(0xFF29211D),
          brightness: Brightness.dark,
        ),
        fontFamilyFallback: const <String>[
          'Noto Sans CJK Local',
          'PingFang SC',
          'PingFang HK',
          'PingFang TC',
          'Hiragino Sans GB',
          'Hiragino Sans CNS',
          'Noto Sans CJK SC',
          'Noto Sans CJK TC',
          'Noto Sans CJK KR',
          'Noto Sans SC',
          'Noto Sans TC',
          'Noto Sans HK',
          'Noto Sans KR',
          'Source Han Sans SC',
          'Source Han Sans TC',
          'Source Han Sans KR',
          'Apple SD Gothic Neo',
          'Malgun Gothic',
          'Meiryo',
          'Microsoft YaHei',
          'WenQuanYi Micro Hei',
          'Arial Unicode MS',
          'sans-serif',
        ],
        textTheme: baseTextTheme.copyWith(
          headlineLarge: baseTextTheme.headlineLarge?.copyWith(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF3E8DE),
          ),
          headlineMedium: baseTextTheme.headlineMedium?.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF3E8DE),
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF3E8DE),
          ),
          bodyLarge: baseTextTheme.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.55,
            color: const Color(0xFFE6D8CD),
          ),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.45,
            color: const Color(0xFFD1BFB2),
          ),
        ),
      ),
      home: OrderingView(
        repository: widget.repository,
        siteName: widget.siteName,
        locale: _locale,
        onThemeModeChanged: _setThemeMode,
        onLocaleChanged: _setLocale,
      ),
    );
  }
}
