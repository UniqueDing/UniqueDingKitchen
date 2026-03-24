import 'package:web/web.dart' as web;

void notifyStartupShellReady() {
  web.window.dispatchEvent(web.CustomEvent('unique-ding-shell-ready'));
}
