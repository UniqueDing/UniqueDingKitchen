import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> downloadQrImage(
  Uint8List pngBytes, {
  required String fileName,
}) async {
  try {
    final parts = JSArray<web.BlobPart>();
    parts.add(pngBytes.toJS);
    final blob = web.Blob(parts, web.BlobPropertyBag(type: 'image/png'));
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> copyQrImageToClipboard(Uint8List pngBytes) async {
  try {
    final parts = JSArray<web.BlobPart>();
    parts.add(pngBytes.toJS);
    final blob = web.Blob(parts, web.BlobPropertyBag(type: 'image/png'));

    final itemData = JSObject();
    itemData['image/png'] = blob;

    final items = JSArray<web.ClipboardItem>();
    items.add(web.ClipboardItem(itemData));
    await web.window.navigator.clipboard.write(items).toDart;
    return true;
  } catch (_) {
    return false;
  }
}
