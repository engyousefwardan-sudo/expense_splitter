import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/add_expense_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/distribution_rules_screen.dart';
import 'screens/payments_screen.dart';
import 'screens/create_pin_screen.dart';
import 'screens/login_screen.dart';
import 'screens/web_viewer_screen.dart';
import 'services/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://bobocqrhueqxsuazhwfa.supabase.co',
    publishableKey: 'sb_publishable_OCLZrfqqrx0WMVVd_HPB9Q_QtR3j75A',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مقسم المصروفات',
      theme: ThemeData(primarySwatch: Colors.teal),
      initialRoute: '/startup',
      routes: {
        '/startup': (context) => const StartupScreen(),
        '/create_pin': (context) => const CreatePinScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/view': (context) {
          final uri = Uri.base;
          final token = uri.queryParameters['token'] ?? '';
          return WebViewerScreen(token: token);
        },
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToCorrectScreen();
    });
  }

  Future<void> _navigateToCorrectScreen() async {
    try {
      if (kIsWeb) {
        final uri = Uri.base;
        final token = uri.queryParameters['token'];
        if (token != null && token.isNotEmpty) {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => WebViewerScreen(token: token)),
            );
          }
          return;
        }
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
        return;
      }

      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      final settings =
          await db.query('settings', where: 'key = ?', whereArgs: ['pin']);

      String route;
      if (settings.isNotEmpty) {
        route = '/login';
      } else {
        route = '/create_pin';
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, route);
      }
    } catch (e) {
      debugPrint('خطأ في StartupScreen: $e');
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/create_pin');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<AddExpenseScreenState> _addExpenseKey =
      GlobalKey<AddExpenseScreenState>();

  int _currentIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      AddExpenseScreen(key: _addExpenseKey),
      const ReportsScreen(),
      const DistributionRulesScreen(),
      const PaymentsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) async {
          if (_currentIndex == 0 &&
              _addExpenseKey.currentState?.hasUnsavedChanges == true) {
            final result = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('فاتورة غير محفوظة'),
                content:
                    const Text('لديك فاتورة غير محفوظة. ماذا تريد أن تفعل؟'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'save'),
                    child: const Text('حفظ ومغادرة'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'discard'),
                    child: const Text('مغادرة بدون حفظ'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'cancel'),
                    child: const Text('إلغاء'),
                  ),
                ],
              ),
            );

            if (result == 'save') {
              final saved = await _addExpenseKey.currentState!.saveInvoice();
              if (saved) {
                setState(() => _currentIndex = index);
              }
            } else if (result == 'discard') {
              _addExpenseKey.currentState!.clearRows();
              _addExpenseKey.currentState!.setUnsaved(false);
              setState(() => _currentIndex = index);
            }
          } else {
            setState(() => _currentIndex = index);
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.add_box), label: 'إدخال'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'تقارير'),
          BottomNavigationBarItem(icon: Icon(Icons.alt_route), label: 'توزيع'),
          BottomNavigationBarItem(icon: Icon(Icons.payment), label: 'دفعات'),
        ],
      ),
    );
  }
}
