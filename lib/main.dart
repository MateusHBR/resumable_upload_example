import 'package:flutter/material.dart';

import 'ui/upload_view.dart';

void main() {
  runApp(const UploadApp());
}

class UploadApp extends StatelessWidget {
  const UploadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const UploadView(title: 'Flutter Demo Home Page'),
    );
  }
}
