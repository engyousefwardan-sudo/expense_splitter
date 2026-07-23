import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../services/database_helper.dart';
import 'web_viewer_screen.dart';

class ShareReportScreen extends StatefulWidget {
  const ShareReportScreen({super.key});

  @override
  State<ShareReportScreen> createState() => _ShareReportScreenState();
}

class _ShareReportScreenState extends State<ShareReportScreen> {
  final supabase = Supabase.instance.client;
  final dbHelper = DatabaseHelper();
  final _pinController = TextEditingController();
  final _uuid = const Uuid();

  Map<String, dynamic>? _activeLink;
  String _message = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActiveLink();
  }

  Future<void> _loadActiveLink() async {
    setState(() => _isLoading = true);
    try {
      if (!kIsWeb) {
        final db = await dbHelper.database;
        final links = await db.query('shared_report_links',
            where: 'is_active = ?', whereArgs: [1]);
        if (links.isNotEmpty) {
          setState(() => _activeLink = links.first);
        }
      } else {
        final links = await supabase
            .from('shared_report_links')
            .select()
            .eq('is_active', true)
            .limit(1);
        if ((links as List).isNotEmpty) {
          setState(() => _activeLink = Map<String, dynamic>.from(links.first));
        }
      }
    } catch (e) {
      _message = 'خطأ: $e';
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String get _webUrl =>
      'https://engyousefwardan-sudo.github.io/expense_splitter/?token=${_activeLink?['token'] ?? ''}';

  Future<void> _createLink() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _message = 'يجب إدخال 6 أرقام');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final token = _uuid.v4();
      final linkData = {
        'id': _uuid.v4(),
        'token': token,
        'pin_code': pin,
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
      };

      if (!kIsWeb) {
        final db = await dbHelper.database;
        await db.insert('shared_report_links', linkData);
      }
      await supabase.from('shared_report_links').insert(linkData);

      await _loadActiveLink();
      _pinController.clear();
      setState(() => _message = 'تم إنشاء الرابط بنجاح');
    } catch (e) {
      setState(() => _message = 'خطأ: $e');
    }
  }

  Future<void> _updatePin() async {
    if (_activeLink == null) return;
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _message = 'يجب إدخال 6 أرقام');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final token = _activeLink!['token'] as String;
      if (!kIsWeb) {
        final db = await dbHelper.database;
        await db.update('shared_report_links', {'pin_code': pin},
            where: 'token = ?', whereArgs: [token]);
      }
      await supabase
          .from('shared_report_links')
          .update({'pin_code': pin}).eq('token', token);
      await _loadActiveLink();
      _pinController.clear();
      setState(() => _message = 'تم تحديث الرمز السري');
    } catch (e) {
      setState(() => _message = 'خطأ: $e');
    }
  }

  Future<void> _deactivateLink() async {
    if (_activeLink == null) return;
    setState(() => _isLoading = true);
    try {
      final token = _activeLink!['token'] as String;
      if (!kIsWeb) {
        final db = await dbHelper.database;
        await db.update('shared_report_links', {'is_active': 0},
            where: 'token = ?', whereArgs: [token]);
      }
      await supabase
          .from('shared_report_links')
          .update({'is_active': false}).eq('token', token);
      setState(() => _activeLink = null);
      setState(() => _message = 'تم إلغاء الرابط');
    } catch (e) {
      setState(() => _message = 'خطأ: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مشاركة التقارير')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_activeLink != null) ...[
                      const Text('الرابط النشط:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('الرابط:'),
                            SelectableText(_webUrl),
                            const SizedBox(height: 8),
                            Text('الرمز السري: ${_activeLink!['pin_code']}'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'رمز سري جديد (6 أرقام)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _updatePin,
                        child: const Text('تحديث الرمز السري'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _deactivateLink,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                        child: const Text('إلغاء الرابط'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('فتح واجهة عبد الآن'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  WebViewerScreen(token: _activeLink!['token']),
                            ),
                          );
                        },
                      ),
                    ] else ...[
                      const Text('لا يوجد رابط نشط. أنشئ رابطاً جديداً:'),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'اختر رمزاً سرياً (6 أرقام)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _createLink,
                        child: const Text('إنشاء رابط'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_message.isNotEmpty)
                      Text(_message,
                          style: const TextStyle(color: Colors.blue)),
                  ],
                ),
              ),
            ),
    );
  }
}
