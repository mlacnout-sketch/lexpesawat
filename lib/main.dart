import 'package:flutter/material.dart';
import 'dashboard.dart';
import 'service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AutoPilotService().init();
  runApp(const ZivpnApp());
}

class ZivpnApp extends StatefulWidget {
  const ZivpnApp({super.key});

  @override
  State<ZivpnApp> createState() => _ZivpnAppState();
}

class _ZivpnAppState extends State<ZivpnApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Ensure timer is running if it should be
      AutoPilotService().onAppResume(); // I need to add this method to Service
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZIVPN NetReset',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const AutoPilotDashboard(),
    );
  }
}