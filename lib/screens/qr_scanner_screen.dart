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
    if (!_hasBarcodeDetector()) {
      setState(() => _error = 'QR scanning not supported in this browser. Try Chrome.');
      return;
    }
    _scanTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _scan());
  }

  bool _hasBarcodeDetector() {
    return _checkBarcodeDetector();
  }

  Future<void> _scan() async {
    if (!_scanning) return;
    try {
      final result = await _detectQR(_video);
      if (result != null && mounted) {
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

@JS('window.BarcodeDetector')
external JSFunction? get _barcodeDetectorCtor;

bool _checkBarcodeDetector() => _barcodeDetectorCtor != null;

Future<String?> _detectQR(web.HTMLVideoElement video) async {
  final options = {'formats': <String>['qr_code'].map((s) => s.toJS).toList().toJS}.jsify()!;
  final detector = _newBarcodeDetector(options);
  final promise = detector.callMethod('detect'.toJS, video as JSObject) as JSPromise<JSArray<JSObject>>;
  final results = await promise.toDart;
  final list = results.toDart;
  if (list.isEmpty) return null;
  final rawValue = list.first.getProperty('rawValue'.toJS);
  if (rawValue == null) return null;
  return (rawValue as JSString).toDart;
}

@JS('BarcodeDetector')
@staticInterop
class _BarcodeDetectorJS {
  external factory _BarcodeDetectorJS(JSAny options);
}

JSObject _newBarcodeDetector(JSAny options) =>
    _BarcodeDetectorJS(options) as JSObject;

extension on JSObject {
  external JSAny? callMethod(JSAny method, [JSAny? arg1]);
  external JSAny? getProperty(JSAny name);
}
