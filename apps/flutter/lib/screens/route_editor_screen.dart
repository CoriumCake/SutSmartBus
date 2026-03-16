import 'package:flutter/material.dart';

class RouteEditorScreen extends StatelessWidget {
  final String? routeId;
  const RouteEditorScreen({super.key, this.routeId});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Route Editor Screen')));
  }
}
