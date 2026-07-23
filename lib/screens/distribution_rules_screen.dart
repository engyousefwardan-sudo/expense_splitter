import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DistributionRulesScreen extends StatefulWidget {
  const DistributionRulesScreen({super.key});

  @override
  State<DistributionRulesScreen> createState() =>
      _DistributionRulesScreenState();
}

class _DistributionRulesScreenState extends State<DistributionRulesScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> rules = [];
  List<Map<String, dynamic>> beneficiaries = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final rulesData = await supabase.from('distribution_rules').select('''
      id, 
      percentage, 
      beneficiary:beneficiary_id(id,name), 
      target:target_beneficiary_id(id,name)
    ''');

    final benData = await supabase.from('beneficiaries').select('id, name');

    setState(() {
      rules = List<Map<String, dynamic>>.from(rulesData);
      beneficiaries = List<Map<String, dynamic>>.from(benData);
      isLoading = false;
    });
  }

  Future<void> deleteRule(String ruleId) async {
    await supabase.from('distribution_rules').delete().eq('id', ruleId);
    loadData();
  }

  Future<void> showAddRuleDialog() async {
    String? selectedBeneficiaryId;
    String? selectedTargetId;
    double percentage = 50;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة قاعدة توزيع'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedBeneficiaryId,
                decoration:
                    const InputDecoration(labelText: 'المستفيد الأساسي'),
                items: beneficiaries.map<DropdownMenuItem<String>>((b) {
                  return DropdownMenuItem<String>(
                    value: b['id'] as String,
                    child: Text(b['name'] as String),
                  );
                }).toList(),
                onChanged: (val) {
                  setDialogState(() => selectedBeneficiaryId = val);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedTargetId,
                decoration: const InputDecoration(labelText: 'يذهب إلى'),
                items: beneficiaries
                    .where((b) => b['id'] != selectedBeneficiaryId)
                    .map<DropdownMenuItem<String>>((b) {
                  return DropdownMenuItem<String>(
                    value: b['id'] as String,
                    child: Text(b['name'] as String),
                  );
                }).toList(),
                onChanged: (val) {
                  setDialogState(() => selectedTargetId = val);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: percentage.toString(),
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'النسبة المئوية (%)'),
                onChanged: (val) {
                  percentage = double.tryParse(val) ?? 50;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedBeneficiaryId != null &&
                    selectedTargetId != null &&
                    percentage > 0 &&
                    percentage <= 100) {
                  await supabase.from('distribution_rules').insert({
                    'beneficiary_id': selectedBeneficiaryId,
                    'target_beneficiary_id': selectedTargetId,
                    'percentage': percentage,
                  });
                  Navigator.pop(ctx);
                  loadData();
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
        title: const Text('قواعد التوزيع'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : rules.isEmpty
              ? const Center(child: Text('لا توجد قواعد توزيع'))
              : ListView.builder(
                  itemCount: rules.length,
                  itemBuilder: (context, index) {
                    final rule = rules[index];
                    final ben = rule['beneficiary'] as Map<String, dynamic>;
                    final target = rule['target'] as Map<String, dynamic>;
                    final percentage = rule['percentage'];

                    return ListTile(
                      title: Text('${ben['name']} → ${target['name']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$percentage%'),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => deleteRule(rule['id']),
                          ),
                        ],
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: showAddRuleDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
