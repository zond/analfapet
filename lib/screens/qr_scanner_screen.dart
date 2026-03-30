import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// QR scanner using the browser's BarcodeDetector API + getUserMedia.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  static int _viewCounter = 0;
  late final String _viewId;
  late final web.HTMLVideoElement _video;
  web.MediaStream? _stream;
  Timer? _scanTimer;
  String? _error;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _viewId = 'qr-scanner-${_viewCounter++}';
    _video = web.HTMLVideoElement()
      ..autoplay = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';

    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int id) => _video);
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final constraints = web.MediaStreamConstraints(
        video: {'facingMode': 'environment'}.jsify()!,
      );
      _stream = await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;
      _video.srcObject = _stream;
      setState(() => _scanning = true);
      _startScanning();
    } catch (e) {
      setState(() => _error = 'Camera access denied');
    }
  }

  void _startScanning() {
    if (!_jsHasBarcodeDetector()) {
      setState(() => _error = 'QR scanning not supported in this browser. Try Chrome.');
      return;
    }
    _scanTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _scan());
  }

  Future<void> _scan() async {
    if (!_scanning) return;
    try {
      final jsResult = await _jsDetectQR(_video).toDart;
      if (jsResult != null && mounted) {
        final result = (jsResult as JSString).toDart;
        _scanning = false;
        Navigator.pop(context, result);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _scanning = false;
    _stream?.getTracks().toDart.forEach((track) => track.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan QR code'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
              ),
            )
          : Stack(
              children: [
                SizedBox.expand(
                  child: HtmlElementView(viewType: _viewId),
                ),
                if (_scanning)
                  const Center(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.fromBorderSide(
                            BorderSide(color: Colors.greenAccent, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// -- JS interop: thin wrappers around helpers defined in index.html --

@JS('_analfapetHasBarcodeDetector')
external bool _jsHasBarcodeDetector();

@JS('_analfapetDetectQR')
external JSPromise<JSAny?> _jsDetectQR(web.HTMLVideoElement video);
