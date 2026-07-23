import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:local_auth/local_auth.dart';
import '../services/database_helper.dart';

class CreatePinScreen extends StatefulWidget {
  const CreatePinScreen({super.key});

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  String _message = '';
  bool _isLoading = false;

  Future<void> _savePin() async {
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (pin.length != 6 || confirmPin.length != 6) {
      setState(() => _message = 'يجب إدخال 6 أرقام');
      return;
    }
    if (pin != confirmPin) {
      setState(() => _message = 'الرقمان غير متطابقين');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      await db.delete('settings');
      await db.insert('settings', {'key': 'pin', 'value': pin});

      if (!kIsWeb) {
        final localAuth = LocalAuthentication();
        final canCheck = await localAuth.canCheckBiometrics;
        if (canCheck) {
          final didAuthenticate = await localAuth.authenticate(
            localizedReason: 'يرجى استخدام بصمة الإصبع لتفعيل الدخول السريع',
          );
          if (didAuthenticate) {
            await db.insert('settings', {'key': 'biometrics', 'value': 'true'});
          }
        }
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      setState(() => _message = 'خطأ: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء رمز الدخول')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 64, color: Colors.teal),
              const SizedBox(height: 24),
              const Text('اختر رمزاً سرياً مكوناً من 6 أرقام'),
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
              TextField(
                controller: _confirmPinController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'تأكيد الرمز السري',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (_message.isNotEmpty)
                Text(_message, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _savePin,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
