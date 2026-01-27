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
    switch (state) {
      case AppLifecycleState.resumed:
        AutoPilotService().onAppResume();
        break;
      case AppLifecycleState.paused:
        // Keep running in background!
        // The service has its own "Anti-Kill" strategy (whitelist/oom_adj).
        print('[Main] App paused, but keeping Watchdog alive.');
        break;
      case AppLifecycleState.detached:
        // Detached usually means the engine is being destroyed.
        // We can try to stop here to be clean, or let it die with the process.
        AutoPilotService().pause();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // No specific action needed for inactive/hidden states
        break;
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