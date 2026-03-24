import 'package:flutter/material.dart';
import 'package:unique_ding_kitchen/app.dart';
import 'package:unique_ding_kitchen/services/runtime_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtimeConfig = await RuntimeConfig.load();
  runApp(
    HomeDiningApp(
      siteName: runtimeConfig.siteName,
      menuSource: runtimeConfig.menuSource,
      trilliumUrl: runtimeConfig.trilliumUrl,
      trilliumTitle: runtimeConfig.trilliumTitle,
    ),
  );
}
