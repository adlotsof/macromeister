// Barcode scan screen using mobile_scanner; resolves the GTIN via
// Open Food Facts and returns a Food? to the caller.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models.dart';
import '../../services/camera_permission.dart';
import '../../services/food_search.dart';
import '../../theme.dart';

/// Pushes a full-screen scanner. Returns the matched [Food], or null if
/// cancelled / not found / lookup failed / camera permission denied.
Future<Food?> showBarcodeScanner(BuildContext context) async {
  final ok = await ensureCameraPermission();
  if (!ok) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Camera permission denied. Enable it in system settings to scan barcodes.')));
    }
    return null;
  }
  if (!context.mounted) return null;
  return Navigator.of(context, rootNavigator: true).push<Food>(
    MaterialPageRoute(builder: (_) => const BarcodeScreen()),
  );
}

class BarcodeScreen extends StatefulWidget {
  const BarcodeScreen({super.key});
  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen> {
  MobileScannerController? _controller;
  bool _done = false;
  String? _status;
  String? _lastCode;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null || code.length < 6) continue;
      if (code == _lastCode) continue; // debounce same-frame repeats
      _lastCode = code;
      setState(() => _status = 'Looking up $code…');
      final food = await lookupOffBarcode(code);
      if (!mounted) return;
      if (food != null) {
        _done = true;
        await _controller?.stop();
        if (mounted) Navigator.of(context).pop(food);
      } else {
        setState(() => _status =
            'Barcode $code not in the food database.\nKeep scanning or go back and search by name.');
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    _controller ??= MobileScannerController(
      formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA],
      detectionSpeed: DetectionSpeed.normal,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: MtTheme.text,
        title: const Text('Scan barcode'),
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller?.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography,
                        size: 40, color: MtTheme.textDim),
                    const SizedBox(height: 12),
                    const Text(
                        'Camera unavailable. Check the camera permission in system settings.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: MtTheme.textDim)),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Go back'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Scan window overlay
          Center(
            child: Container(
              width: 260,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: MtTheme.accent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _status ?? 'Point the camera at a product barcode',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: MtTheme.text),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
