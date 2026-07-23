import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> payments = [];
  List<Map<String, dynamic>> beneficiaries = [];
  bool isLoading = true;
  String? defaultPayerId;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final benResponse =
          await supabase.from('beneficiaries').select('id, name');
      final List<Map<String, dynamic>> benList = (benResponse as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final yosef = benList.cast<Map<String, dynamic>?>().firstWhere(
            (b) => b != null && (b['name'] as String).trim() == 'يوسف',
            orElse: () => null,
          );
      if (yosef != null) {
        defaultPayerId = yosef['id'] as String;
      }

      final payResponse = await supabase
          .from('payments')
          .select('id, total_amount, date, notes, payer:payer_id(name)')
          .order('date', ascending: false);

      final List<Map<String, dynamic>> payList = (payResponse as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        beneficiaries = benList;
        payments = payList;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }
  }

  Future<void> showAddPaymentDialog() async {
    final totalController = TextEditingController();
    final notesController = TextEditingController();
    String? selectedPayerId = defaultPayerId;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تسجيل دفعة جديدة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedPayerId,
                  decoration: const InputDecoration(labelText: 'الدافع'),
                  items: beneficiaries.map<DropdownMenuItem<String>>((b) {
                    return DropdownMenuItem<String>(
                      value: b['id'] as String,
                      child: Text(b['name'] as String),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setDialogState(() => selectedPayerId = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: totalController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'المبلغ المدفوع'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration:
                      const InputDecoration(labelText: 'ملاحظات (اختياري)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final total = double.tryParse(totalController.text) ?? 0;
                if (selectedPayerId == null || total <= 0) return;

                try {
                  final payResponse = await supabase
                      .from('payments')
                      .insert({
                        'payer_id': selectedPayerId,
                        'total_amount': total,
                        'date':
                            DateTime.now().toIso8601String().split('T').first,
                        'notes': notesController.text.trim(),
                      })
                      .select('id')
                      .single();

                  final paymentId = payResponse['id'] as String;

                  await supabase.from('payment_allocations').insert({
                    'payment_id': paymentId,
                    'beneficiary_id': selectedPayerId,
                    'amount': total,
                  });

                  Navigator.pop(ctx);
                  loadData();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('فشل في حفظ الدفعة: $e')),
                    );
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الدفعات'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : payments.isEmpty
              ? const Center(child: Text('لا توجد دفعات مسجلة'))
              : ListView.builder(
                  itemCount: payments.length,
                  itemBuilder: (context, index) {
                    final p = payments[index];
                    final payer = p['payer'] != null
                        ? (p['payer'] as Map<String, dynamic>)['name'] ?? ''
                        : '';
                    return ListTile(
                      title: Text(
                          '${p['date']} - ${p['total_amount']} (دافع: $payer)'),
                      subtitle: Text(p['notes'] ?? ''),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: showAddPaymentDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
