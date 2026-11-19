import 'package:flutter/material.dart';
import '../config.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/top_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = const ApiService();
  late final TextEditingController urlController =
      TextEditingController(text: AppConfig.apiBaseUrl.value);
  bool checking = false;
  bool? reachable;

  Future<void> checkConnection() async {
    print('checkConnection: checking connection to ${AppConfig.apiBaseUrl.value}');
    setState(() {
      checking = true;
      reachable = null;
    });
    final ok = await _api.ping();
    print('ok');
    print(ok);
    if (mounted) setState(() {
      checking = false;
      reachable = ok;
    });
  }

  void save() {
    final v = urlController.text.trim();
    if (v.isEmpty) return;
    AppConfig.apiBaseUrl.value = v;
    lectureStore.refresh();
    checkConnection();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backend URL updated.')));
  }

  @override
  void initState() {
    super.initState();
    checkConnection();
  }

  @override
  Widget build(BuildContext c) => _Frame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TopBar(title: 'Settings', subtitle: 'Configure the connection to your backend API.', search: false),
            const SizedBox(height: 24),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Backend Connection', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      const Text('Where the FastAPI lecture-processing service is running.',
                          style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                      const SizedBox(height: 20),
                      const Text('API base URL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: urlController,
                        decoration: const InputDecoration(hintText: 'http://127.0.0.1:8000'),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        AppGradientButton(label: 'Save', icon: Icons.save_rounded, onPressed: save),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: checking ? null : checkConnection,
                          icon: const Icon(Icons.wifi_tethering_rounded, size: 17),
                          label: Text(checking ? 'Checking...' : 'Test Connection'),
                        ),
                        const SizedBox(width: 12),
                        if (reachable != null)
                          Icon(
                            reachable! ? Icons.check_circle_rounded : Icons.error_rounded,
                            color: reachable! ? AppColors.green : Colors.redAccent,
                          ),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Endpoints Used', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 14),
                      _endpoint('POST /api/lectures/upload'),
                      _endpoint('POST /api/lectures/{id}/process'),
                      _endpoint('GET  /api/lectures/{id}/status'),
                      _endpoint('GET  /api/lectures/{id}/download'),
                      _endpoint('GET  /api/lectures'),
                      _endpoint('POST /api/lectures/{id}/convert-pdf'),
                      _endpoint('GET  /api/lectures/{id}/download-pdf'),
                    ],
                  ),
                ),
              ),
            ]),
          ],
        ),
      );

  Widget _endpoint(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(children: [
          const Icon(Icons.circle, color: AppColors.purple2, size: 6),
          const SizedBox(width: 9),
          Expanded(
              child: Text(s,
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.muted, fontFamily: 'monospace'))),
        ]),
      );
}

class _Frame extends StatelessWidget {
  final Widget child;
  const _Frame({required this.child});
  @override
  Widget build(BuildContext c) =>
      SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(34, 28, 34, 40), child: child));
}
