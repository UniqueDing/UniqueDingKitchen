import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:unique_ding_kitchen/l10n/app_localizations.dart';
import 'package:unique_ding_kitchen/services/qr_image_actions.dart';

class ShareDialog extends StatefulWidget {
  const ShareDialog({
    super.key,
    required this.shareUri,
    required this.siteName,
  });

  final Uri shareUri;
  final String siteName;

  @override
  State<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<ShareDialog> {
  final GlobalKey _qrCaptureKey = GlobalKey();
  Uint8List? _qrPngBytes;

  @override
  void initState() {
    super.initState();
    _prepareQrBytes();
  }

  Future<void> _prepareQrBytes() async {
    await WidgetsBinding.instance.endOfFrame;
    final bytes = await _captureRenderedQrBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      _qrPngBytes = bytes;
    });
  }

  Future<void> _downloadQrImage(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    if (_qrPngBytes == null) {
      final bytes = await _captureRenderedQrBytes();
      if (bytes != null) {
        _qrPngBytes = bytes;
      }
    }

    if (!context.mounted) {
      return;
    }

    if (_qrPngBytes == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.qrPreparingTryAgain)));
      return;
    }

    final downloaded = await downloadQrImage(
      _qrPngBytes!,
      fileName: 'order-qr.png',
    );
    if (!context.mounted) {
      return;
    }
    if (downloaded) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.qrImageDownloaded)));
      return;
    }

    final copied = await copyQrImageToClipboard(_qrPngBytes!);
    if (!context.mounted) {
      return;
    }
    if (copied) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.qrImageCopied)));
      return;
    }

    await Clipboard.setData(ClipboardData(text: widget.shareUri.toString()));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.shareLinkCopied)));
  }

  Future<Uint8List?> _captureRenderedQrBytes() async {
    final boundary =
        _qrCaptureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      return null;
    }
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      return null;
    }
    return bytes.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [Color(0xFF2E2622), Color(0xFF231D1A)]
                  : const [Color(0xFFFFF8F1), Color(0xFFF8EBD9)],
            ),
            border: Border.all(
              color: isDark ? const Color(0xFF5A4A42) : const Color(0xFFE6D5C8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.12),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _downloadQrImage(context),
                  child: RepaintBoundary(
                    key: _qrCaptureKey,
                    child: Container(
                      width: 220,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE8DED4)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 200,
                            height: 200,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                QrImageView(
                                  data: widget.shareUri.toString(),
                                  version: QrVersions.auto,
                                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                                  size: 184,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Color(0xFF2C1D18),
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Color(0xFF2C1D18),
                                  ),
                                ),
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: SvgPicture.asset(
                                    'web/favicon.svg',
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Icon(
                                        Icons.restaurant_menu_rounded,
                                        color: Color(0xFF7A4337),
                                        size: 22,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.siteName,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: const Color(0xFF2C1D18),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _downloadQrImage(context),
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: Text(l10n.downloadQr),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.close),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
