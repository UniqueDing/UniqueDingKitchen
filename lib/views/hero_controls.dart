import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:unique_ding_kitchen/l10n/app_localizations.dart';

class HeroCardPanel extends StatelessWidget {
  const HeroCardPanel({
    super.key,
    required this.siteName,
    required this.locale,
    required this.onThemeModeChanged,
    required this.onLocaleChanged,
    required this.onOpenShare,
  });

  final String siteName;
  final Locale locale;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<Locale> onLocaleChanged;
  final VoidCallback onOpenShare;

  @override
  Widget build(BuildContext context) {
    final selectedLanguage = locale.languageCode;
    final textTheme = Theme.of(context).textTheme;
    final isDarkModeActive = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x241C120F),
                blurRadius: 24,
                offset: Offset(0, 14),
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDarkModeActive
                  ? const [Color(0xCC5E382F), Color(0xB333231E)]
                  : const [Color(0xD9B96550), Color(0xB8744337)],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      siteName,
                      style: textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('open-share-dialog'),
                    onPressed: onOpenShare,
                    tooltip: AppLocalizations.of(context)!.shareTooltip,
                    icon: const Icon(Icons.qr_code_rounded, size: 18),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      minimumSize: const Size(30, 30),
                      fixedSize: const Size(30, 30),
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ThemeSlideToggle(
                    isDark: isDarkModeActive,
                    onChanged: (value) => onThemeModeChanged(
                      value ? ThemeMode.dark : ThemeMode.light,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 30,
                    height: 30,
                    padding: EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.24),
                      ),
                    ),
                    child: PopupMenuButton<String>(
                      key: const Key('language-dropdown'),
                      tooltip: '',
                      padding: EdgeInsets.zero,
                      position: PopupMenuPosition.under,
                      color: const Color(0xFF50342B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 52,
                        maxWidth: 56,
                      ),
                      itemBuilder: (context) => const <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'zh',
                          height: 36,
                          padding: EdgeInsets.zero,
                          child: Center(child: Text('🇨🇳')),
                        ),
                        PopupMenuItem<String>(
                          value: 'en',
                          height: 36,
                          padding: EdgeInsets.zero,
                          child: Center(child: Text('🇺🇸')),
                        ),
                        PopupMenuItem<String>(
                          value: 'ja',
                          height: 36,
                          padding: EdgeInsets.zero,
                          child: Center(child: Text('🇯🇵')),
                        ),
                        PopupMenuItem<String>(
                          value: 'ko',
                          height: 36,
                          padding: EdgeInsets.zero,
                          child: Center(child: Text('🇰🇷')),
                        ),
                      ],
                      onSelected: (value) => onLocaleChanged(Locale(value)),
                      child: Center(
                        child: Text(
                          _languageFlag(selectedLanguage),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _languageFlag(String code) {
  switch (code) {
    case 'zh':
      return '🇨🇳';
    case 'en':
      return '🇺🇸';
    case 'ja':
      return '🇯🇵';
    case 'ko':
      return '🇰🇷';
    default:
      return '🇺🇸';
  }
}

class ThemeSlideToggle extends StatelessWidget {
  const ThemeSlideToggle({
    super.key,
    required this.isDark,
    required this.onChanged,
  });

  final bool isDark;
  final ValueChanged<bool> onChanged;

  static const Duration _motionDuration = Duration(milliseconds: 240);
  static const Curve _motionCurve = Curves.fastOutSlowIn;

  @override
  Widget build(BuildContext context) {
    final trackColor = Colors.white.withValues(alpha: 0.16);
    final borderColor = Colors.white.withValues(alpha: 0.24);
    final inactiveIconColor = Colors.white.withValues(alpha: 0.72);
    final knobIconColor = isDark
        ? const Color(0xFF6B5AF4)
        : const Color(0xFFF2A83B);

    return Semantics(
      label: AppLocalizations.of(context)!.darkModeLabel,
      toggled: isDark,
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: const Key('theme-slide-toggle'),
          borderRadius: BorderRadius.circular(999),
          onTap: () => onChanged(!isDark),
          child: AnimatedContainer(
            duration: _motionDuration,
            curve: _motionCurve,
            width: 66,
            height: 30,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: trackColor,
              border: Border.all(color: borderColor),
            ),
            child: Stack(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      width: 30,
                      height: 24,
                      child: Center(
                        child: Icon(
                          Icons.light_mode_rounded,
                          size: 13,
                          color: isDark ? inactiveIconColor : Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 30,
                      height: 24,
                      child: Center(
                        child: Icon(
                          Icons.dark_mode_rounded,
                          size: 13,
                          color: isDark ? Colors.white : inactiveIconColor,
                        ),
                      ),
                    ),
                  ],
                ),
                AnimatedAlign(
                  duration: _motionDuration,
                  curve: _motionCurve,
                  alignment: isDark
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: _motionDuration,
                    curve: _motionCurve,
                    width: 30,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white, const Color(0xFFF1F1F1)],
                      ),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(999),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.55),
                          blurRadius: 1,
                          offset: const Offset(0, -1),
                        ),
                      ],
                    ),
                    child: Icon(
                      isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      size: 12,
                      color: knobIconColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
