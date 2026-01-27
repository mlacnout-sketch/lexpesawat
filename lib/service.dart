import 'dart:async';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shizuku_api/shizuku_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kAppPackageName = 'com.zivpn.netreset';

class AutoPilotConfig {
  final int checkIntervalSeconds;
  final int connectionTimeoutSeconds;
  final int maxFailCount;
  final int airplaneModeDelaySeconds;
  final int recoveryWaitSeconds;
  final bool autoHealthCheck;
  final bool enablePingStabilizer;
  final int stabilizerSizeMb;

  const AutoPilotConfig({
    this.checkIntervalSeconds = 15,
    this.connectionTimeoutSeconds = 5,
    this.maxFailCount = 3,
    this.airplaneModeDelaySeconds = 3,
    this.recoveryWaitSeconds = 10,
    this.autoHealthCheck = false,
    this.enablePingStabilizer = false,
    this.stabilizerSizeMb = 1,
  });

  AutoPilotConfig copyWith({
    int? checkIntervalSeconds,
    int? connectionTimeoutSeconds,
    int? maxFailCount,
    int? airplaneModeDelaySeconds,
    int? recoveryWaitSeconds,
    bool? autoHealthCheck,
    bool? enablePingStabilizer,
    int? stabilizerSizeMb,
  }) {
    return AutoPilotConfig(
      checkIntervalSeconds: checkIntervalSeconds ?? this.checkIntervalSeconds,
      connectionTimeoutSeconds: connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      maxFailCount: maxFailCount ?? this.maxFailCount,
      airplaneModeDelaySeconds: airplaneModeDelaySeconds ?? this.airplaneModeDelaySeconds,
      recoveryWaitSeconds: recoveryWaitSeconds ?? this.recoveryWaitSeconds,
      autoHealthCheck: autoHealthCheck ?? this.autoHealthCheck,
      enablePingStabilizer: enablePingStabilizer ?? this.enablePingStabilizer,
      stabilizerSizeMb: stabilizerSizeMb ?? this.stabilizerSizeMb,
    );
  }

  @override
  String toString() {
    return 'AutoPilotConfig(interval: $checkIntervalSeconds, timeout: $connectionTimeoutSeconds, maxFail: $maxFailCount, resetDelay: $airplaneModeDelaySeconds, recoveryWait: $recoveryWaitSeconds, autoHealth: $autoHealthCheck, stabilizer: $enablePingStabilizer, size: $stabilizerSizeMb)';
  }
}

enum AutoPilotStatus {
  stopped,
  running,
  checking,
  recovering,
  error,
}

class AutoPilotState {
  final AutoPilotStatus status;
  final int failCount;
  final int consecutiveResets; 
  final String? message;
  final DateTime? lastCheck;
  final bool hasInternet;

  const AutoPilotState({
    required this.status,
    required this.failCount,
    this.consecutiveResets = 0, 
    this.message,
    this.lastCheck,
    required this.hasInternet,
  });

  AutoPilotState copyWith({
    AutoPilotStatus? status,
    int? failCount,
    int? consecutiveResets,
    String? message,
    DateTime? lastCheck,
    bool? hasInternet,
  }) {
    return AutoPilotState(
      status: status ?? this.status,
      failCount: failCount ?? this.failCount,
      consecutiveResets: consecutiveResets ?? this.consecutiveResets,
      message: message ?? this.message,
      lastCheck: lastCheck ?? this.lastCheck,
      hasInternet: hasInternet ?? this.hasInternet,
    );
  }
}

class AutoPilotService {
  static final AutoPilotService _instance = AutoPilotService._internal();
  factory AutoPilotService() => _instance;
  AutoPilotService._internal();

  final _shizuku = ShizukuApi();
  final _httpClient = http.Client();
  static const _platform = MethodChannel('com.zivpn.netreset/service');
  
  Timer? _timer;
  AutoPilotConfig _config = const AutoPilotConfig();
  
  final _stateController = StreamController<AutoPilotState>.broadcast();
  Stream<AutoPilotState> get stateStream => _stateController.stream;
  
  bool _isChecking = false;

  AutoPilotState _currentState = const AutoPilotState(
    status: AutoPilotStatus.stopped,
    failCount: 0,
    consecutiveResets: 0,
    hasInternet: true,
  );

  AutoPilotState get currentState => _currentState;
  AutoPilotConfig get config => _config;
  bool get isRunning => _currentState.status != AutoPilotStatus.stopped;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _config = AutoPilotConfig(
        checkIntervalSeconds: prefs.getInt('checkIntervalSeconds') ?? 15,
        connectionTimeoutSeconds: prefs.getInt('connectionTimeoutSeconds') ?? 5,
        maxFailCount: prefs.getInt('maxFailCount') ?? 3,
        airplaneModeDelaySeconds: prefs.getInt('airplaneModeDelaySeconds') ?? 3,
        recoveryWaitSeconds: prefs.getInt('recoveryWaitSeconds') ?? 10,
        autoHealthCheck: prefs.getBool('autoHealthCheck') ?? false,
        enablePingStabilizer: prefs.getBool('enablePingStabilizer') ?? false,
        stabilizerSizeMb: prefs.getInt('stabilizerSizeMb') ?? 1,
      );
      print('Config loaded successfully: $_config');
    } catch (e) {
      print('Failed to load config: $e');
    }
  }

  Future<void> _saveConfig(AutoPilotConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('checkIntervalSeconds', config.checkIntervalSeconds);
      await prefs.setInt('connectionTimeoutSeconds', config.connectionTimeoutSeconds);
      await prefs.setInt('maxFailCount', config.maxFailCount);
      await prefs.setInt('airplaneModeDelaySeconds', config.airplaneModeDelaySeconds);
      await prefs.setInt('recoveryWaitSeconds', config.recoveryWaitSeconds);
      await prefs.setBool('autoHealthCheck', config.autoHealthCheck);
      await prefs.setBool('enablePingStabilizer', config.enablePingStabilizer);
      await prefs.setInt('stabilizerSizeMb', config.stabilizerSizeMb);
    } catch (e) {
      print('Failed to save config: $e');
      rethrow;
    }
  }

  Future<void> updateConfig(AutoPilotConfig newConfig) async {
    final wasRunning = isRunning;
    if (wasRunning) {
      stop();
    }
    _config = newConfig;
    await _saveConfig(newConfig);
    if (wasRunning) {
      start();
    }
  }

  Future<void> start() async {
    if (isRunning) return;

    try {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.running,
        message: 'Initializing Shizuku service...', 
      ));

      final isBinderAlive = await _shizuku.pingBinder() ?? false;
      if (!isBinderAlive) {
        throw 'Shizuku service is not running.';
      }

      if (!(await _shizuku.checkPermission() ?? false)) {
        final granted = await _shizuku.requestPermission() ?? false;
        if (!granted) {
          throw 'Shizuku Permission Denied';
        }
      }

      // Start Native Foreground Service
      try {
        await _platform.invokeMethod('startForeground');
      } catch (e) {
        print('[AutoPilotService] Failed to start foreground service: $e');
      }

      await _strengthenBackground();

      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.running,
        failCount: 0,
        message: 'Watchdog started',
      ));

      _timer = Timer.periodic(
        Duration(seconds: _config.checkIntervalSeconds),
        (timer) async {
          await _checkAndRecover();
        },
      );
    } catch (e) {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Failed to start: $e',
      ));
      rethrow;
    }
  }

  Future<void> _strengthenBackground() async {
    try {
      const pkg = kAppPackageName; 
      await _shizuku.runCommand('dumpsys deviceidle whitelist +$pkg');
      await _shizuku.runCommand('cmd activity set-inactive $pkg false');
      await _shizuku.runCommand('cmd activity set-standby-bucket $pkg active');
      await _shizuku.runCommand(
        'pidof $pkg | xargs -n 1 -I {} sh -c "echo -900 > /proc/{}/oom_score_adj"'
      );
      print('[_strengthenBackground] Anti-Kill Applied');
    } catch (e) {
      print('[_strengthenBackground] Warning: $e');
    }
  }

  void stop() {
    try {
      _platform.invokeMethod('stopForeground');
    } catch (e) {
      print('[AutoPilotService] Failed to stop foreground service: $e');
    }

    _timer?.cancel();
    _timer = null;
    
    _updateState(_currentState.copyWith(
      status: AutoPilotStatus.stopped,
      failCount: 0,
      message: 'Watchdog stopped',
    ));
  }

  Future<void> _checkAndRecover() async {
    if (!isRunning || _isChecking) return;
    _isChecking = true;

    try {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.checking,
        lastCheck: DateTime.now(),
      ));

      await _strengthenBackground();

      final hasInternet = await checkInternet();

      if (hasInternet) {
        if (_currentState.failCount > 0 || _currentState.consecutiveResets > 0) {
          _updateState(_currentState.copyWith(
            status: AutoPilotStatus.running,
            failCount: 0,
            consecutiveResets: 0, 
            hasInternet: true,
            message: 'Internet connection stable',
          ));
        } else {
          _updateState(_currentState.copyWith(
            status: AutoPilotStatus.running,
            hasInternet: true,
            message: 'Connection stable',
          ));
        }
      } else {
        final newFailCount = _currentState.failCount + 1;
        
        _updateState(_currentState.copyWith(
          status: AutoPilotStatus.running,
          failCount: newFailCount,
          hasInternet: false,
          message: 'Connection lost ($newFailCount/${_config.maxFailCount})',
        ));

        if (newFailCount >= _config.maxFailCount) {
          if (_currentState.consecutiveResets >= 5) {
             _updateState(_currentState.copyWith(
               status: AutoPilotStatus.stopped,
               message: 'Gave up: Internet unstable after 5 resets.',
             ));
             stop(); 
          } else {
             await _performReset();
          }
        }
      }
    } catch (e) {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Check failed: $e',
      ));
    } finally {
      _isChecking = false;
    }
  }

  Future<bool> checkInternet() async {
    try {
      final response = await _httpClient
          .head(Uri.parse('http://connectivitycheck.gstatic.com/generate_204'))
          .timeout(Duration(seconds: _config.connectionTimeoutSeconds));

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      print('[AutoPilotService] Internet check failed: $e');
      return false;
    }
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    print('[AutoPilotService] Paused background timer');
  }

  void onAppResume() {
    Future.delayed(const Duration(milliseconds: 800), () async {
      print('[AutoPilotService] App resumed. Performing health check...');
      try {
        final isBinderAlive = await _shizuku.pingBinder() ?? false;
        if (!isBinderAlive) {
          print('[AutoPilotService] Warning: Shizuku binder died.');
        }
      } catch (e) {
         print('[AutoPilotService] Binder check failed: $e');
      }

      if (isRunning && (_timer == null || !_timer!.isActive)) {
        print('[AutoPilotService] Restarting background timer...');
        _timer = Timer.periodic(
          Duration(seconds: _config.checkIntervalSeconds),
          (timer) async {
            await _checkAndRecover();
          },
        );
        _checkAndRecover();
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _httpClient.close();
    _stateController.close();
  }

  Future<void> _runPingStabilizer() async {
    if (!_config.enablePingStabilizer) return;

    final client = http.Client(); // Use fresh client for new network state

    try {
      _updateState(_currentState.copyWith(
        message: 'Stabilizing: Warming up connection...',
      ));
      
      // Allow modem/DNS to settle after airplane mode toggle
      await Future.delayed(const Duration(seconds: 2));

      for (int i = 1; i <= _config.stabilizerSizeMb; i++) {
        if (!isRunning) break; 
        
        try {
          _updateState(_currentState.copyWith(
            message: 'Stabilizing: Downloading chunk $i/${_config.stabilizerSizeMb} MB...',
          ));

          final request = http.Request('GET', Uri.parse('http://speedtest.tele2.net/1MB.zip'));
          // Disable keep-alive to force fresh connection per chunk
          request.headers['Connection'] = 'close'; 
          
          final response = await client.send(request).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            await for (var _ in response.stream) {
              if (!isRunning) break;
              // Discard bytes
            }
          } else {
             print('[PingStabilizer] Chunk $i failed: ${response.statusCode}');
             // Small delay on fail before next chunk
             await Future.delayed(const Duration(seconds: 1));
          }
        } catch (e) {
          print('[PingStabilizer] Chunk $i error: $e');
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      
      print('[PingStabilizer] Sequence completed.');
    } catch (e) {
      print('[PingStabilizer] Critical error: $e');
    } finally {
      client.close();
    }
  }

  Future<void> _performReset({int retryCount = 0}) async {
      try {
        _updateState(_currentState.copyWith(
          status: AutoPilotStatus.recovering,
          failCount: 0,
          consecutiveResets: _currentState.consecutiveResets + 1,
          message: retryCount > 0 ? 'Retrying reset (${retryCount + 1})...' : 'Resetting network (Attempt #${_currentState.consecutiveResets + 1})...',
        ));
  
        await _shizuku.runCommand('cmd connectivity airplane-mode enable');
        await Future.delayed(Duration(seconds: _config.airplaneModeDelaySeconds));
        if (!isRunning) return;
  
        _updateState(_currentState.copyWith(
          message: 'Restoring connection...',
        ));
  
        await _shizuku.runCommand('cmd connectivity airplane-mode disable');
        await Future.delayed(Duration(seconds: _config.recoveryWaitSeconds));
        if (!isRunning) return;

        // Verify connection before stabilizing
        _updateState(_currentState.copyWith(message: 'Verifying connectivity...'));
        final isConnected = await checkInternet();

        if (isConnected) {
           // Connection is back! Run Stabilizer to wake it up fully.
           await _runPingStabilizer();
        } else {
           print('[AutoPilotService] Skip stabilizer: No internet after reset.');
        }
  
        _updateState(_currentState.copyWith(
          status: AutoPilotStatus.running,
          message: 'Recovery process completed',
        ));
      } catch (e) {
        if (retryCount < 2) {
           print('[AutoPilotService] Reset failed, retrying... Error: $e');
           await Future.delayed(const Duration(seconds: 2));
           return _performReset(retryCount: retryCount + 1);
        }
        
        final errorMsg = e.toString();
        _updateState(_currentState.copyWith(
          status: AutoPilotStatus.error,
          message: 'Reset error: ${errorMsg.length > 50 ? "${errorMsg.substring(0, 47)}..." : errorMsg}',
        ));
      }
    }

  void _updateState(AutoPilotState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }
}