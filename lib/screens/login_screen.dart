import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/database_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pinController = TextEditingController();
  final _localAuth = LocalAuthentication();
  final _supabase = Supabase.instance.client;
  String _message = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tryBiometrics();
  }

  Future<void> _tryBiometrics() async {
    if (kIsWeb) return;

    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      final settings = await db
          .query('settings', where: 'key = ?', whereArgs: ['biometrics']);
      final biometricsEnabled =
          settings.isNotEmpty && settings.first['value'] == 'true';

      if (biometricsEnabled) {
        final didAuthenticate = await _localAuth.authenticate(
          localizedReason: 'يرجى استخدام بصمة الإصبع للدخول',
        );
        if (didAuthenticate && mounted) {
          await _performFullSync();
        }
      }
    } catch (_) {}
  }

  Future<void> _loginWithPin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _message = 'يجب إدخال 6 أرقام');
      return;
    }

    setState(() => _isLoading = true);
    setState(() => _message = '');
    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      final settings =
          await db.query('settings', where: 'key = ?', whereArgs: ['pin']);

      if (settings.isNotEmpty && settings.first['value'] == pin) {
        await _performFullSync();
      } else {
        setState(() => _message = 'الرمز السري غير صحيح');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _message = 'خطأ: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _performFullSync() async {
    setState(() {
      _isLoading = true;
      _message = 'جاري المزامنة مع السحابة...';
    });

    try {
      final dbHelper = DatabaseHelper();
      final hasConnection = await _checkInternet();

      if (hasConnection) {
        await _fullSync(dbHelper);
      }
    } catch (e) {
      debugPrint('خطأ في المزامنة: $e');
    }

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await _supabase.from('beneficiaries').select().limit(1);
      return result != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _fullSync(DatabaseHelper dbHelper) async {
    // 1. تنزيل البيانات المرجعية
    final beneficiaries = await _supabase.from('beneficiaries').select();
    for (var b in beneficiaries) {
      await dbHelper.insertBeneficiary({
        'id': b['id'],
        'name': b['name'],
        'created_at': b['created_at']?.toString(),
      });
    }

    final categories = await _supabase.from('categories').select();
    for (var c in categories) {
      await dbHelper.insertCategory({
        'id': c['id'],
        'name': c['name'],
        'created_at': c['created_at']?.toString(),
      });
    }

    final items = await _supabase.from('items').select();
    for (var i in items) {
      await dbHelper.insertItem({
        'id': i['id'],
        'name': i['name'],
        'category_id': i['category_id'],
        'usage_count': i['usage_count'] ?? 0,
        'created_at': i['created_at']?.toString(),
      });
    }

    // 2. تنزيل جميع الفواتير
    final invoices = await _supabase.from('invoices').select();
    for (var inv in invoices) {
      final invoiceId = inv['id'] as String;
      await dbHelper.insertInvoice({
        'id': invoiceId,
        'date': inv['date']?.toString(),
        'notes': inv['notes']?.toString(),
        'is_synced': 1,
        'created_at': inv['created_at']?.toString(),
      });

      final itemsData = await _supabase
          .from('invoice_items')
          .select()
          .eq('invoice_id', invoiceId);
      for (var item in itemsData) {
        await dbHelper.insertInvoiceItem({
          'id': item['id'],
          'invoice_id': item['invoice_id'],
          'item_id': item['item_id'],
          'quantity': item['quantity'],
          'unit_price': item['unit_price'],
          'total': item['total'],
          'original_beneficiary_id': item['original_beneficiary_id'],
          'is_synced': 1,
          'created_at': item['created_at']?.toString(),
        });

        final allocs = await _supabase
            .from('invoice_item_allocations')
            .select()
            .eq('invoice_item_id', item['id']);
        for (var alloc in allocs) {
          await dbHelper.insertInvoiceItemAllocation({
            'id': alloc['id'],
            'invoice_item_id': alloc['invoice_item_id'],
            'beneficiary_id': alloc['beneficiary_id'],
            'amount': alloc['amount'],
            'is_synced': 1,
            'created_at': alloc['created_at']?.toString(),
          });
        }
      }
    }

    // 3. تنزيل الدفعات
    final payments = await _supabase.from('payments').select();
    for (var pay in payments) {
      final paymentId = pay['id'] as String;
      await dbHelper.insertPayment({
        'id': paymentId,
        'payer_id': pay['payer_id'],
        'total_amount': pay['total_amount'],
        'date': pay['date']?.toString(),
        'notes': pay['notes']?.toString(),
        'is_synced': 1,
        'created_at': pay['created_at']?.toString(),
      });

      final payAllocs = await _supabase
          .from('payment_allocations')
          .select()
          .eq('payment_id', paymentId);
      for (var pa in payAllocs) {
        await dbHelper.insertPaymentAllocation({
          'id': pa['id'],
          'payment_id': pa['payment_id'],
          'beneficiary_id': pa['beneficiary_id'],
          'amount': pa['amount'],
          'is_synced': 1,
          'created_at': pa['created_at']?.toString(),
        });
      }
    }

    // 4. رفع الفواتير المحلية غير المزامنة
    await _syncLocalToCloud(dbHelper);
  }

  Future<void> _syncLocalToCloud(DatabaseHelper dbHelper) async {
    final unsynced = await dbHelper.getUnsyncedInvoices();
    for (var inv in unsynced) {
      final invoiceId = inv['id'] as String;
      final dateStr = inv['date'] as String? ??
          DateTime.now().toIso8601String().split('T').first;
      try {
        await _supabase
            .from('invoices')
            .insert({'id': invoiceId, 'date': dateStr});

        final items = await dbHelper.getUnsyncedItems(invoiceId);
        for (var item in items) {
          await _supabase.from('invoice_items').insert({
            'id': item['id'],
            'invoice_id': item['invoice_id'],
            'item_id': item['item_id'],
            'quantity': item['quantity'],
            'unit_price': item['unit_price'],
          });
          final allocs =
              await dbHelper.getUnsyncedAllocations(item['id'] as String);
          for (var alloc in allocs) {
            await _supabase.from('invoice_item_allocations').insert({
              'id': alloc['id'],
              'invoice_item_id': alloc['invoice_item_id'],
              'beneficiary_id': alloc['beneficiary_id'],
              'amount': alloc['amount'],
            });
          }
        }
        await dbHelper.markInvoiceAsSynced(invoiceId);
      } catch (e) {
        debugPrint('فشل رفع الفاتورة $invoiceId: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 64, color: Colors.teal),
              const SizedBox(height: 24),
              if (_isLoading)
                Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_message, style: const TextStyle(fontSize: 16)),
                  ],
                )
              else ...[
                const Text('أدخل الرمز السري (6 أرقام)'),
                const SizedBox(height: 24),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'الرمز السري',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (_message.isNotEmpty)
                  Text(_message, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loginWithPin,
                  child: const Text('دخول'),
                ),
                const SizedBox(height: 24),
                if (!kIsWeb)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('الدخول بالبصمة'),
                    onPressed: _tryBiometrics,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
