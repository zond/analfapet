import 'package:flutter/material.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showToast(String message) {
  scaffoldMessengerKey.currentState
    ?..clearMaterialBanners()
    ..showMaterialBanner(
      MaterialBanner(
        content: Text(message),
        backgroundColor: const Color(0xFF6D3410),
        actions: [
          TextButton(
            onPressed: () => scaffoldMessengerKey.currentState?.clearMaterialBanners(),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  Future.delayed(const Duration(seconds: 3), () {
    scaffoldMessengerKey.currentState?.clearMaterialBanners();
  });
}
