import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shizuku_api/shizuku_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoPilotConfig {
  final int checkIntervalSeconds;
  final int connectionTimeoutSeconds;
  final int maxFailCount;
  final int airplaneModeDelaySeconds;
  final int recoveryWaitSeconds;
  final bool autoHealthCheck;

  const AutoPilotConfig({
    this.checkIntervalSeconds = 15,
    this.connectionTimeoutSeconds = 5,
    this.maxFailCount = 3,
    this.airplaneModeDelaySeconds = 3,
    this.recoveryWaitSeconds = 10,
    this.autoHealthCheck = false,
  });

  AutoPilotConfig copyWith({
    int? checkIntervalSeconds,
    int? connectionTimeoutSeconds,
    int? maxFailCount,
    int? airplaneModeDelaySeconds,
    int? recoveryWaitSeconds,
    bool? autoHealthCheck,
  }) {
    return AutoPilotConfig(
      checkIntervalSeconds: checkIntervalSeconds ?? this.checkIntervalSeconds,
      connectionTimeoutSeconds: connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      maxFailCount: maxFailCount ?? this.maxFailCount,
      airplaneModeDelaySeconds: airplaneModeDelaySeconds ?? this.airplaneModeDelaySeconds,
      recoveryWaitSeconds: recoveryWaitSeconds ?? this.recoveryWaitSeconds,
      autoHealthCheck: autoHealthCheck ?? this.autoHealthCheck,
    );
  }

  @override
  String toString() {
    return 'AutoPilotConfig(interval: $checkIntervalSeconds, timeout: $connectionTimeoutSeconds, maxFail: $maxFailCount, resetDelay: $airplaneModeDelaySeconds, recoveryWait: $recoveryWaitSeconds, autoHealth: $autoHealthCheck)';
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
  final String? message;
  final DateTime? lastCheck;
  final bool hasInternet;

  const AutoPilotState({
    required this.status,
    required this.failCount,
    this.message,
    this.lastCheck,
    required this.hasInternet,
  });

  AutoPilotState copyWith({
    AutoPilotStatus? status,
    int? failCount,
    String? message,
    DateTime? lastCheck,
    bool? hasInternet,
  }) {
    return AutoPilotState(
      status: status ?? this.status,
      failCount: failCount ?? this.failCount,
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
  
  Timer? _timer;
  AutoPilotConfig _config = const AutoPilotConfig();
  
  final _stateController = StreamController<AutoPilotState>.broadcast();
  Stream<AutoPilotState> get stateStream => _stateController.stream;
  
  AutoPilotState _currentState = const AutoPilotState(
    status: AutoPilotStatus.stopped,
    failCount: 0,
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
      );
      // ignore: avoid_print
      print('Config loaded successfully: $_config');
    } catch (e) {
      // ignore: avoid_print
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
    } catch (e) {
      // ignore: avoid_print
      print('Failed to save config: $e');
    }
  }

  void updateConfig(AutoPilotConfig newConfig) {
    final wasRunning = isRunning;
    if (wasRunning) {
      stop();
    }
    _config = newConfig;
    _saveConfig(newConfig);
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
      // Use current package name
      const pkg = 'com.zivpn.netreset'; 
      
      await _shizuku.runCommand('dumpsys deviceidle whitelist +$pkg');
      await _shizuku.runCommand('cmd activity set-inactive $pkg false');
      await _shizuku.runCommand('cmd activity set-standby-bucket $pkg active');
      
      // OOM Score Logic
      await _shizuku.runCommand(
        'pidof $pkg | xargs -n 1 -I {} sh -c "echo -900 > /proc/{}/oom_score_adj"'
      );
      
      // ignore: avoid_print
      print('[_strengthenBackground] Anti-Kill Applied');
    } catch (e) {
      // ignore: avoid_print
      print('[_strengthenBackground] Warning: $e');
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    
    _updateState(_currentState.copyWith(
      status: AutoPilotStatus.stopped,
      failCount: 0,
      message: 'Watchdog stopped',
    ));
  }

  Future<void> _checkAndRecover() async {
    if (!isRunning) return;

    try {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.checking,
        lastCheck: DateTime.now(),
      ));

      await _strengthenBackground();

      final hasInternet = await checkInternet();

      if (hasInternet) {
        if (_currentState.failCount > 0) {
          _updateState(_currentState.copyWith(
            status: AutoPilotStatus.running,
            failCount: 0,
            hasInternet: true,
            message: 'Internet connection recovered',
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
          await _performReset();
        }
      }
    } catch (e) {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Check failed: $e',
      ));
    }
  }

  Future<bool> checkInternet() async {
    try {
      final response = await http
          .head(Uri.parse('http://connectivitycheck.gstatic.com/generate_204'))
          .timeout(Duration(seconds: _config.connectionTimeoutSeconds));

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

    Future<void> _performReset() async {
      try {
        _updateState(_currentState.copyWith(
          status: AutoPilotStatus.recovering,
          failCount: 0,
          message: 'Initiating connection recovery...',
        ));
  
        await _shizuku.runCommand('cmd connectivity airplane-mode enable');
        
        // Wait for delay, but check if we should abort
        await Future.delayed(Duration(seconds: _config.airplaneModeDelaySeconds));
        if (!isRunning) return;
  
        _updateState(_currentState.copyWith(
          message: 'Restoring connection...',
        ));
  
        await _shizuku.runCommand('cmd connectivity airplane-mode disable');
        
        // Wait for recovery, check if abort
        await Future.delayed(Duration(seconds: _config.recoveryWaitSeconds));
        if (!isRunning) return;
  
        _updateState(_currentState.copyWith(
          status: AutoPilotStatus.running,
          message: 'Recovery process completed',
        ));
      } catch (e) {
        _updateState(_currentState.copyWith(
          status: AutoPilotStatus.error,
          message: 'Reset error: $e',
        ));
      }
    }
  void _updateState(AutoPilotState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _timer?.cancel();
    _stateController.close();
  }

  void onAppResume() {
    if (isRunning && (_timer == null || !_timer!.isActive)) {
        _timer?.cancel();
        _timer = Timer.periodic(
          Duration(seconds: _config.checkIntervalSeconds),
          (timer) async {
            await _checkAndRecover();
          },
        );
        _checkAndRecover();
    }
  }
}
