import 'package:flutter/material.dart';
import 'service.dart';

class AutoPilotSettingsPage extends StatefulWidget {
  const AutoPilotSettingsPage({Key? key}) : super(key: key);

  @override
  State<AutoPilotSettingsPage> createState() => _AutoPilotSettingsPageState();
}

class _AutoPilotSettingsPageState extends State<AutoPilotSettingsPage> {
  final _service = AutoPilotService();
  late AutoPilotConfig _config;

  @override
  void initState() {
    super.initState();
    _config = _service.config;
  }

  void _updateConfig(AutoPilotConfig newConfig) {
    setState(() {
      _config = newConfig;
    });
    _service.updateConfig(newConfig);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings updated successfully'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _resetToDefaults() {
    _updateConfig(const AutoPilotConfig());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchdog Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: _resetToDefaults,
            tooltip: 'Reset to defaults',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoCard(),
          const SizedBox(height: 24),
          _buildTimeoutSection(),
          const SizedBox(height: 24),
          _buildRecoverySection(),
          const SizedBox(height: 24),
          _buildAdvancedSection(),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Configure connection monitoring and auto-reset behavior.',
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeoutSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection Monitoring',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildSliderSetting(
              title: 'Check Interval',
              description: 'How often to check internet connection',
              value: _config.checkIntervalSeconds.toDouble(),
              min: 5,
              max: 60,
              divisions: 11,
              unit: 'seconds',
              onChanged: (value) {
                _updateConfig(_config.copyWith(
                  checkIntervalSeconds: value.toInt(),
                ));
              },
            ),
            const Divider(height: 32),
            _buildSliderSetting(
              title: 'Connection Timeout',
              description: 'Maximum wait time for ping check',
              value: _config.connectionTimeoutSeconds.toDouble(),
              min: 2,
              max: 15,
              divisions: 13,
              unit: 'seconds',
              onChanged: (value) {
                _updateConfig(_config.copyWith(
                  connectionTimeoutSeconds: value.toInt(),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecoverySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recovery Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildSliderSetting(
              title: 'Max Fail Count',
              description: 'Failed attempts before triggering reset',
              value: _config.maxFailCount.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              unit: 'attempts',
              onChanged: (value) {
                _updateConfig(_config.copyWith(
                  maxFailCount: value.toInt(),
                ));
              },
            ),
            const Divider(height: 32),
            _buildSliderSetting(
              title: 'Airplane Mode Delay',
              description: 'Time to stay in airplane mode',
              value: _config.airplaneModeDelaySeconds.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              unit: 'seconds',
              onChanged: (value) {
                _updateConfig(_config.copyWith(
                  airplaneModeDelaySeconds: value.toInt(),
                ));
              },
            ),
            const Divider(height: 32),
            _buildSliderSetting(
              title: 'Recovery Wait Time',
              description: 'Time to wait after disabling airplane mode',
              value: _config.recoveryWaitSeconds.toDouble(),
              min: 5,
              max: 30,
              divisions: 5,
              unit: 'seconds',
              onChanged: (value) {
                _updateConfig(_config.copyWith(
                  recoveryWaitSeconds: value.toInt(),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSection() {
    final totalCycleTime = _config.checkIntervalSeconds * _config.maxFailCount;
    final recoveryTime = _config.airplaneModeDelaySeconds + _config.recoveryWaitSeconds;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cycle Summary',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildSummaryItem(
              'Time until trigger',
              '~${totalCycleTime} seconds',
              Icons.timer,
            ),
            const SizedBox(height: 12),
            _buildSummaryItem(
              'Reset duration',
              '~${recoveryTime} seconds',
              Icons.refresh,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderSetting({
    required String title,
    required String description,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: textTheme.bodySmall?.copyWith(
                      color: textTheme.bodySmall?.color?.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${value.toInt()} $unit',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
