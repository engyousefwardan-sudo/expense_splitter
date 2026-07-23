import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/database_helper.dart';
import 'share_report_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final supabase = Supabase.instance.client;
  final dbHelper = DatabaseHelper();

  List<Map<String, dynamic>> beneficiaries = [];
  String? selectedBeneficiaryId;
  String currentBeneficiaryName = '';

  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> items = [];
  List<Map<String, dynamic>> tags = [];
  String? selectedCategoryId;
  String? selectedCategoryName;
  String? selectedItemId;
  String? selectedItemName;
  String? selectedTagId;

  DateTime? fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? toDate = DateTime.now();

  List<Map<String, dynamic>> transactions = [];
  bool isLoading = true;

  bool get isAnalyticMode =>
      selectedCategoryId != null ||
      selectedItemId != null ||
      selectedTagId != null;

  @override
  void initState() {
    super.initState();
    loadFilterData();
    loadBeneficiaries();
  }

  // -------------------- تحميل البيانات --------------------
  Future<void> loadFilterData() async {
    if (!kIsWeb) {
      try {
        final db = await dbHelper.database;
        final cats = await db.query('categories');
        final allItems = await db.query('items');
        final allTags = await db.query('tags');
        setState(() {
          categories = cats;
          items = allItems;
          tags = allTags;
        });
      } catch (_) {}
    } else {
      final cats = await supabase.from('categories').select('id, name');
      final allItems =
          await supabase.from('items').select('id, name, category_id');
      final allTags = await supabase.from('tags').select('id, name');
      setState(() {
        categories = List<Map<String, dynamic>>.from(cats);
        items = List<Map<String, dynamic>>.from(allItems);
        tags = List<Map<String, dynamic>>.from(allTags);
      });
    }
  }

  Future<void> loadBeneficiaries() async {
    List<Map<String, dynamic>> data;
    if (!kIsWeb) {
      try {
        final db = await dbHelper.database;
        data = await db.query('beneficiaries');
      } catch (_) {
        data = [];
      }
    } else {
      data = List<Map<String, dynamic>>.from(
        await supabase.from('beneficiaries').select('id, name'),
      );
    }
    setState(() {
      beneficiaries = data;
      final yosef = beneficiaries.cast<Map<String, dynamic>?>().firstWhere(
            (b) => b != null && (b['name'] as String).trim() == 'يوسف',
            orElse: () => null,
          );
      if (yosef != null) {
        selectBeneficiary(yosef['id'] as String, yosef['name'] as String);
      } else if (beneficiaries.isNotEmpty) {
        selectBeneficiary(beneficiaries.first['id'] as String,
            beneficiaries.first['name'] as String);
      }
    });
  }

  void selectBeneficiary(String id, String name) {
    setState(() {
      selectedBeneficiaryId = id;
      currentBeneficiaryName = name;
    });
    loadTransactions();
  }

  // -------------------- الفلاتر --------------------
  void applyFilters() {
    loadTransactions();
  }

  void clearFilters() {
    setState(() {
      selectedCategoryId = null;
      selectedCategoryName = null;
      selectedItemId = null;
      selectedItemName = null;
      selectedTagId = null;
    });
    loadTransactions();
  }

  Future<void> pickDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: fromDate != null && toDate != null
          ? DateTimeRange(start: fromDate!, end: toDate!)
          : null,
      helpText: 'اختر الفترة',
      cancelText: 'إلغاء',
      confirmText: 'موافق',
      fieldStartLabelText: 'من تاريخ',
      fieldEndLabelText: 'إلى تاريخ',
    );

    if (picked != null) {
      setState(() {
        fromDate = picked.start;
        toDate = picked.end;
      });
      applyFilters();
    }
  }

  void clearDateFilter() {
    setState(() {
      fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
      toDate = DateTime.now();
    });
    applyFilters();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'اختر';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool _isDateInRange(String dateStr) {
    if (fromDate == null && toDate == null) return true;
    if (dateStr.isEmpty) return true;
    final date = DateTime.tryParse(dateStr);
    if (date == null) return true;
    if (fromDate != null && date.isBefore(fromDate!)) return false;
    if (toDate != null && date.isAfter(toDate!)) return false;
    return true;
  }

  Future<void> _confirmDeleteAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحذير!'),
        content: const Text(
            'هل أنت متأكد من مسح جميع البيانات؟\nهذه العملية لا يمكن التراجع عنها.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح الكل'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => isLoading = true);
      try {
        // قيمة UUID صفرية تستخدم كشرط لحذف الكل
        final zeroUuid = '00000000-0000-0000-0000-000000000000';

        // مسح البيانات المحلية (للهاتف)
        if (!kIsWeb) {
          await dbHelper.clearAllData();
        }

        // مسح البيانات من السحابة
        await supabase
            .from('invoice_item_tags')
            .delete()
            .neq('invoice_item_id', zeroUuid);
        await supabase
            .from('invoice_item_allocations')
            .delete()
            .neq('id', zeroUuid);
        await supabase.from('invoice_items').delete().neq('id', zeroUuid);
        await supabase.from('invoices').delete().neq('id', zeroUuid);
        await supabase.from('payment_allocations').delete().neq('id', zeroUuid);
        await supabase.from('payments').delete().neq('id', zeroUuid);
        await supabase.from('distribution_rules').delete().neq('id', zeroUuid);
        await supabase.from('tags').delete().neq('id', zeroUuid);

        setState(() {
          transactions = [];
          isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم مسح جميع البيانات بنجاح')),
          );
        }
      } catch (e) {
        setState(() => isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل في مسح البيانات: $e')),
          );
        }
      }
    }
  }

  // -------------------- قلب النظام: جلب المعاملات --------------------
  Future<void> loadTransactions() async {
    if (selectedBeneficiaryId == null) return;
    setState(() => isLoading = true);

    try {
      final bool isMom = (currentBeneficiaryName == 'الأم');
      final bool isSon =
          (currentBeneficiaryName == 'يوسف' || currentBeneficiaryName == 'عبد');
      final String benId = selectedBeneficiaryId!;

      String? momId;
      if (isSon) {
        final mom = beneficiaries.cast<Map<String, dynamic>?>().firstWhere(
              (b) => b != null && (b['name'] as String).trim() == 'الأم',
              orElse: () => null,
            );
        momId = mom?['id'] as String?;
      }

      final List<Map<String, dynamic>> allEvents = [];

      if (!kIsWeb) {
        final db = await dbHelper.database;

        if (isMom) {
          String itemQuery = '''
            SELECT ii.id, ii.total, ii.item_id, ii.invoice_id, ii.created_at, inv.date
            FROM invoice_items ii
            JOIN invoices inv ON ii.invoice_id = inv.id
            WHERE ii.original_beneficiary_id = ?
          ''';
          List<dynamic> itemParams = [benId];

          if (selectedItemId != null) {
            itemQuery += ' AND ii.item_id = ?';
            itemParams.add(selectedItemId!);
          } else if (selectedCategoryId != null) {
            itemQuery +=
                ' AND ii.item_id IN (SELECT id FROM items WHERE category_id = ?)';
            itemParams.add(selectedCategoryId!);
          }
          if (selectedTagId != null) {
            itemQuery +=
                ' AND ii.id IN (SELECT invoice_item_id FROM invoice_item_tags WHERE tag_id = ?)';
            itemParams.add(selectedTagId!);
          }
          itemQuery += ' ORDER BY ii.created_at ASC';

          final momItems = await db.rawQuery(itemQuery, itemParams);

          for (var item in momItems) {
            final date = item['date'] as String? ?? '';
            if (!_isDateInRange(date)) continue;

            final itemId = item['item_id'] as String;
            final prodInfo = await db.rawQuery(
              'SELECT i.name, c.name AS cat_name FROM items i LEFT JOIN categories c ON i.category_id = c.id WHERE i.id = ?',
              [itemId],
            );
            final itemName =
                prodInfo.isNotEmpty ? prodInfo.first['name'] ?? '' : '';
            final catName =
                prodInfo.isNotEmpty ? prodInfo.first['cat_name'] ?? '' : '';

            allEvents.add({
              'created_at':
                  DateTime.tryParse(item['created_at'] as String? ?? '') ??
                      DateTime.now(),
              'date': date,
              'description': 'شراء $itemName',
              'category': catName,
              'type': 'expense',
              'amount': (item['total'] as num).toDouble(),
              'is_mom_expense': false,
              'event_type': 'expense',
            });
          }
        } else {
          String query = '''
            SELECT iia.amount, iia.invoice_item_id, iia.created_at,
                   ii.item_id, ii.original_beneficiary_id,
                   inv.date
            FROM invoice_item_allocations iia
            JOIN invoice_items ii ON iia.invoice_item_id = ii.id
            JOIN invoices inv ON ii.invoice_id = inv.id
            WHERE iia.beneficiary_id = ?
          ''';
          List<dynamic> params = [benId];

          if (selectedItemId != null) {
            query += ' AND ii.item_id = ?';
            params.add(selectedItemId!);
          } else if (selectedCategoryId != null) {
            query +=
                ' AND ii.item_id IN (SELECT id FROM items WHERE category_id = ?)';
            params.add(selectedCategoryId!);
          }
          if (selectedTagId != null) {
            query +=
                ' AND iia.invoice_item_id IN (SELECT invoice_item_id FROM invoice_item_tags WHERE tag_id = ?)';
            params.add(selectedTagId!);
          }

          query += ' ORDER BY iia.created_at ASC';

          final allocs = await db.rawQuery(query, params);

          for (var row in allocs) {
            final date = row['date'] as String? ?? '';
            if (!_isDateInRange(date)) continue;

            final String? origBenId = row['original_beneficiary_id'] as String?;
            final bool isMomExpense = (momId != null && origBenId == momId);
            if (isAnalyticMode && isMomExpense) continue;

            final itemId = row['item_id'] as String? ?? '';
            List<Map<String, dynamic>> prodInfo = [];
            if (itemId.isNotEmpty) {
              prodInfo = await db.rawQuery(
                'SELECT i.name, c.name AS cat_name FROM items i LEFT JOIN categories c ON i.category_id = c.id WHERE i.id = ?',
                [itemId],
              );
            }
            final itemName =
                prodInfo.isNotEmpty ? prodInfo.first['name'] ?? '' : '';
            final catName =
                prodInfo.isNotEmpty ? prodInfo.first['cat_name'] ?? '' : '';

            allEvents.add({
              'created_at':
                  DateTime.tryParse(row['created_at'] as String? ?? '') ??
                      DateTime.now(),
              'date': date,
              'description': 'شراء $itemName',
              'category': catName,
              'type': 'expense',
              'amount': (row['amount'] as num).toDouble(),
              'is_mom_expense': isMomExpense,
              'event_type': 'expense',
            });
          }
        }

        if (!isAnalyticMode) {
          final payments = await db.rawQuery('''
            SELECT pa.amount, pa.created_at, p.date, p.payer_id, b.name AS payer_name
            FROM payment_allocations pa
            JOIN payments p ON pa.payment_id = p.id
            LEFT JOIN beneficiaries b ON p.payer_id = b.id
            WHERE pa.beneficiary_id = ?
            ORDER BY pa.created_at ASC
          ''', [benId]);

          for (var p in payments) {
            allEvents.add({
              'created_at':
                  DateTime.tryParse(p['created_at'] as String? ?? '') ??
                      DateTime.now(),
              'date': p['date'] as String? ?? '',
              'description': 'دفعة (دافع: ${p['payer_name'] ?? ''})',
              'type': 'payment',
              'amount': (p['amount'] as num).toDouble(),
              'event_type': 'payment',
            });
          }
        }
      } else {
        if (isMom) {
          var itemQuery = supabase
              .from('invoice_items')
              .select(
                  'id, total, item_id, invoice_id, created_at, invoices!inner(date)')
              .eq('original_beneficiary_id', benId);

          if (selectedItemId != null) {
            itemQuery = itemQuery.eq('item_id', selectedItemId!);
          } else if (selectedCategoryId != null) {
            final filteredIds = items
                .where((i) => i['category_id'] == selectedCategoryId)
                .map((i) => i['id'] as String)
                .toList();
            if (filteredIds.isNotEmpty) {
              itemQuery = itemQuery.inFilter('item_id', filteredIds);
            } else {
              itemQuery = itemQuery.eq('item_id', 'no-match');
            }
          }
          if (selectedTagId != null) {
            final taggedItems = await supabase
                .from('invoice_item_tags')
                .select('invoice_item_id')
                .eq('tag_id', selectedTagId!);
            final List<String> taggedItemIds = (taggedItems as List)
                .map((e) => e['invoice_item_id'] as String)
                .toList();
            if (taggedItemIds.isNotEmpty) {
              itemQuery = itemQuery.inFilter('id', taggedItemIds);
            } else {
              itemQuery = itemQuery.eq('id', 'no-match');
            }
          }

          final momItems = await itemQuery.order('created_at', ascending: true);

          for (var item in momItems) {
            final inv = item['invoices'] as Map<String, dynamic>;
            final date = inv['date'] as String? ?? '';
            if (!_isDateInRange(date)) continue;

            final itemId = item['item_id'] as String;
            final prodData = await supabase
                .from('items')
                .select('name, categories(name)')
                .eq('id', itemId)
                .maybeSingle();
            final itemName = prodData?['name'] ?? '';
            final catName =
                (prodData?['categories'] as Map<String, dynamic>?)?['name'] ??
                    '';

            allEvents.add({
              'created_at':
                  DateTime.tryParse(item['created_at'] as String? ?? '') ??
                      DateTime.now(),
              'date': date,
              'description': 'شراء $itemName',
              'category': catName,
              'type': 'expense',
              'amount': (item['total'] as num).toDouble(),
              'is_mom_expense': false,
              'event_type': 'expense',
            });
          }
        } else {
          var query = supabase
              .from('invoice_item_allocations')
              .select(
                  'amount, invoice_item_id, created_at, invoice_items!inner(item_id, original_beneficiary_id, invoice_id, invoices!inner(date))')
              .eq('beneficiary_id', benId);

          if (selectedItemId != null) {
            query = query.eq('invoice_items.item_id', selectedItemId!);
          } else if (selectedCategoryId != null) {
            final filteredIds = items
                .where((i) => i['category_id'] == selectedCategoryId)
                .map((i) => i['id'] as String)
                .toList();
            if (filteredIds.isNotEmpty) {
              query = query.inFilter('invoice_items.item_id', filteredIds);
            } else {
              query = query.eq('invoice_items.item_id', 'no-match');
            }
          }

          final allocs = await query.order('created_at', ascending: true);

          for (var alloc in allocs) {
            final item = alloc['invoice_items'] as Map<String, dynamic>;
            final inv = item['invoices'] as Map<String, dynamic>;
            final date = inv['date'] as String? ?? '';

            if (!_isDateInRange(date)) continue;

            final String? origBenId =
                item['original_beneficiary_id'] as String?;
            final bool isMomExpense = (momId != null && origBenId == momId);
            if (isAnalyticMode && isMomExpense) continue;

            final itemId = item['item_id'] as String;
            final prodData = await supabase
                .from('items')
                .select('name, categories(name)')
                .eq('id', itemId)
                .maybeSingle();
            final itemName = prodData?['name'] ?? '';
            final catName =
                (prodData?['categories'] as Map<String, dynamic>?)?['name'] ??
                    '';

            allEvents.add({
              'created_at':
                  DateTime.tryParse(alloc['created_at'] as String? ?? '') ??
                      DateTime.now(),
              'date': date,
              'description': 'شراء $itemName',
              'category': catName,
              'type': 'expense',
              'amount': (alloc['amount'] as num).toDouble(),
              'is_mom_expense': isMomExpense,
              'event_type': 'expense',
            });
          }
        }

        if (!isAnalyticMode) {
          final payments = await supabase
              .from('payment_allocations')
              .select('amount, created_at, payments!inner(date, payer_id)')
              .eq('beneficiary_id', benId)
              .order('created_at', ascending: true);

          for (var p in payments) {
            final pay = p['payments'] as Map<String, dynamic>;
            final payerData = await supabase
                .from('beneficiaries')
                .select('name')
                .eq('id', pay['payer_id'])
                .maybeSingle();
            final payerName = payerData?['name'] ?? '';

            allEvents.add({
              'created_at':
                  DateTime.tryParse(p['created_at'] as String? ?? '') ??
                      DateTime.now(),
              'date': pay['date'] as String? ?? '',
              'description': 'دفعة (دافع: $payerName)',
              'type': 'payment',
              'amount': (p['amount'] as num).toDouble(),
              'event_type': 'payment',
            });
          }
        }
      }

      allEvents.sort((a, b) =>
          (a['created_at'] as DateTime).compareTo(b['created_at'] as DateTime));

      if (isAnalyticMode) {
        final List<Map<String, dynamic>> merged = [];
        double runningTotal = 0;
        for (var event in allEvents) {
          merged.add(event);
          runningTotal += event['amount'] as double;
        }
        if (merged.isNotEmpty) {
          merged.add({
            'date': '------',
            'description': 'الإجمالي',
            'type': 'total',
            'amount': runningTotal,
            'is_total': true,
          });
        }
        setState(() => transactions = merged);
      } else {
        List<Map<String, dynamic>> merged = [];
        if (isMom) {
          String? currentMonthKey;
          double monthlyTotal = 0;
          List<Map<String, dynamic>> monthEvents = [];
          for (var event in allEvents) {
            final dateStr = event['date'] as String;
            final monthKey = dateStr.substring(0, 7);
            if (currentMonthKey != null && monthKey != currentMonthKey) {
              if (monthEvents.isNotEmpty) {
                merged.addAll(monthEvents);
                merged.add({
                  'date': '------',
                  'description': 'إجمالي شهر $currentMonthKey',
                  'type': 'month_total',
                  'amount': monthlyTotal,
                  'is_month_total': true,
                });
              }
              monthEvents = [];
              monthlyTotal = 0;
            }
            currentMonthKey = monthKey;
            monthEvents.add(event);
            monthlyTotal += event['amount'] as double;
          }
          if (monthEvents.isNotEmpty) {
            merged.addAll(monthEvents);
            merged.add({
              'date': '------',
              'description': 'إجمالي شهر ${currentMonthKey ?? ''}',
              'type': 'month_total',
              'amount': monthlyTotal,
              'is_month_total': true,
            });
          }
        } else {
          List<Map<String, dynamic>> pendingMomShares = [];
          int cycleCounter = 1;
          for (var event in allEvents) {
            if (event['event_type'] == 'expense') {
              if (isSon && event['is_mom_expense'] == true) {
                pendingMomShares.add(event);
              } else {
                merged.add(event);
              }
            } else if (event['event_type'] == 'payment') {
              if (pendingMomShares.isNotEmpty) {
                double total = pendingMomShares.fold(
                    0, (sum, e) => sum + (e['amount'] as double));
                merged.add({
                  'date': '------',
                  'description': 'مصروفات شقة الأم (دورة $cycleCounter)',
                  'type': 'mom_share',
                  'amount': total,
                  'is_mom': true,
                });
                cycleCounter++;
                pendingMomShares.clear();
              }
              merged.add(event);
            }
          }
          if (pendingMomShares.isNotEmpty) {
            double total = pendingMomShares.fold(
                0, (sum, e) => sum + (e['amount'] as double));
            merged.add({
              'date': '------',
              'description': 'مصروفات شقة الأم (دورة $cycleCounter)',
              'type': 'mom_share',
              'amount': total,
              'is_mom': true,
            });
          }
        }
        setState(() => transactions = merged);
      }
    } catch (e) {
      debugPrint('خطأ في تحميل التقرير: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  // -------------------- دوال القوائم المنسدلة (السهم) --------------------
  void _showCategoryMenu(BuildContext context, TextEditingController controller,
      Function(String, String) onSelected) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset offset = box.localToGlobal(Offset.zero);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(offset.dx, offset.dy + box.size.height,
          offset.dx + box.size.width, offset.dy + box.size.height + 300),
      items: categories.map((cat) {
        final name = cat['name'] as String;
        return PopupMenuItem<String>(value: name, child: Text(name));
      }).toList(),
    ).then((selected) {
      if (selected != null) {
        final cat = categories.firstWhere((c) => c['name'] == selected);
        controller.text = selected;
        onSelected(cat['id'] as String, selected);
      }
    });
  }

  void _showItemMenu(BuildContext context, TextEditingController controller,
      Function(String, String) onSelected) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset offset = box.localToGlobal(Offset.zero);
    final filteredItems = selectedCategoryId == null
        ? items
        : items.where((i) => i['category_id'] == selectedCategoryId).toList();
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(offset.dx, offset.dy + box.size.height,
          offset.dx + box.size.width, offset.dy + box.size.height + 300),
      items: filteredItems.map((item) {
        final name = item['name'] as String;
        return PopupMenuItem<String>(value: name, child: Text(name));
      }).toList(),
    ).then((selected) {
      if (selected != null) {
        final item = items.firstWhere((i) => i['name'] == selected);
        controller.text = selected;
        onSelected(item['id'] as String, selected);
      }
    });
  }

  // -------------------- واجهة المستخدم --------------------
  @override
  Widget build(BuildContext context) {
    double cumulativeBalance = 0;
    double reportTotal = 0;

    List<Map<String, dynamic>> filteredItems = selectedCategoryId == null
        ? items
        : items.where((i) => i['category_id'] == selectedCategoryId).toList();

    if (isAnalyticMode) {
      for (var tx in transactions) {
        if (tx['type'] != 'total') {
          reportTotal += (tx['amount'] as num).toDouble();
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isAnalyticMode
            ? 'تقرير: $currentBeneficiaryName'
            : 'كشف حساب: $currentBeneficiaryName'),
        actions: [
          PopupMenuButton<String>(
            icon: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: Colors.teal, size: 28),
            ),
            onSelected: (String id) {
              final ben = beneficiaries.firstWhere((b) => b['id'] == id);
              selectBeneficiary(id, ben['name'] as String);
            },
            itemBuilder: (BuildContext context) {
              return beneficiaries.map((b) {
                return PopupMenuItem<String>(
                    value: b['id'] as String, child: Text(b['name'] as String));
              }).toList();
            },
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.black),
            tooltip: 'مشاركة التقارير',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ShareReportScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            tooltip: 'مسح جميع البيانات',
            onPressed: () => _confirmDeleteAllData(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.grey[100],
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: pickDateRange,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'الفترة',
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            '${_formatDate(fromDate)}  →  ${_formatDate(toDate)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: clearDateFilter,
                      tooltip: 'إعادة تعيين للشهر الحالي',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Autocomplete<String>(
                        key: ValueKey(
                            'cat_filter_${selectedCategoryName ?? ''}'),
                        initialValue:
                            TextEditingValue(text: selectedCategoryName ?? ''),
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          final input = textEditingValue.text.trim();
                          if (input.isEmpty)
                            return const Iterable<String>.empty();
                          return categories
                              .where((c) => (c['name'] as String)
                                  .toLowerCase()
                                  .contains(input.toLowerCase()))
                              .map((c) => c['name'] as String)
                              .toList();
                        },
                        onSelected: (String selection) {
                          final cat = categories
                              .firstWhere((c) => c['name'] == selection);
                          setState(() {
                            selectedCategoryId = cat['id'] as String;
                            selectedCategoryName = selection;
                            selectedItemId = null;
                            selectedItemName = null;
                          });
                          applyFilters();
                        },
                        fieldViewBuilder: (context, textEditingController,
                            focusNode, onFieldSubmitted) {
                          focusNode.addListener(() {
                            if (!focusNode.hasFocus) {
                              final currentText =
                                  textEditingController.text.trim();
                              if (currentText.isNotEmpty) {
                                final exactMatch = categories.any((c) =>
                                    (c['name'] as String).toLowerCase() ==
                                    currentText.toLowerCase());
                                if (!exactMatch && selectedCategoryId != null) {
                                  setState(() {
                                    selectedCategoryId = null;
                                    selectedCategoryName = null;
                                    selectedItemId = null;
                                    selectedItemName = null;
                                  });
                                  applyFilters();
                                }
                              }
                            }
                          });
                          return TextFormField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'التصنيف',
                              contentPadding: EdgeInsets.zero,
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.arrow_drop_down),
                                onPressed: () {
                                  _showCategoryMenu(
                                      context, textEditingController,
                                      (catId, catName) {
                                    setState(() {
                                      selectedCategoryId = catId;
                                      selectedCategoryName = catName;
                                      selectedItemId = null;
                                      selectedItemName = null;
                                    });
                                    applyFilters();
                                  });
                                },
                              ),
                            ),
                            onFieldSubmitted: (String value) =>
                                onFieldSubmitted(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Autocomplete<String>(
                        key: ValueKey('item_filter_${selectedItemName ?? ''}'),
                        initialValue:
                            TextEditingValue(text: selectedItemName ?? ''),
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          final input = textEditingValue.text.trim();
                          if (input.isEmpty)
                            return const Iterable<String>.empty();
                          return filteredItems
                              .where((i) => (i['name'] as String)
                                  .toLowerCase()
                                  .contains(input.toLowerCase()))
                              .map((i) => i['name'] as String)
                              .toList();
                        },
                        onSelected: (String selection) {
                          final item =
                              items.firstWhere((i) => i['name'] == selection);
                          setState(() {
                            selectedItemId = item['id'] as String;
                            selectedItemName = selection;
                          });
                          applyFilters();
                        },
                        fieldViewBuilder: (context, textEditingController,
                            focusNode, onFieldSubmitted) {
                          focusNode.addListener(() {
                            if (!focusNode.hasFocus) {
                              final currentText =
                                  textEditingController.text.trim();
                              if (currentText.isNotEmpty) {
                                final exactMatch = items.any((i) =>
                                    (i['name'] as String).toLowerCase() ==
                                    currentText.toLowerCase());
                                if (!exactMatch && selectedItemId != null) {
                                  setState(() {
                                    selectedItemId = null;
                                    selectedItemName = null;
                                  });
                                  applyFilters();
                                }
                              }
                            }
                          });
                          return TextFormField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'الصنف',
                              contentPadding: EdgeInsets.zero,
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.arrow_drop_down),
                                onPressed: () {
                                  _showItemMenu(context, textEditingController,
                                      (itemId, itemName) {
                                    setState(() {
                                      selectedItemId = itemId;
                                      selectedItemName = itemName;
                                    });
                                    applyFilters();
                                  });
                                },
                              ),
                            ),
                            onFieldSubmitted: (String value) =>
                                onFieldSubmitted(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedTagId,
                        decoration: const InputDecoration(
                            labelText: 'الوسم',
                            contentPadding: EdgeInsets.zero),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('الكل')),
                          ...tags.map((tag) => DropdownMenuItem<String>(
                                value: tag['id'] as String,
                                child: Text(tag['name'] as String),
                              )),
                        ],
                        onChanged: (val) {
                          setState(() => selectedTagId = val);
                          applyFilters();
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear_all),
                      onPressed: clearFilters,
                      tooltip: 'مسح الكل',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : transactions.isEmpty
                    ? const Center(child: Text('لا توجد معاملات'))
                    : Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              color: Colors.grey[200],
                              child: Row(
                                children: [
                                  const Expanded(
                                      flex: 2,
                                      child: Text('التاريخ',
                                          textAlign: TextAlign.center)),
                                  const Expanded(
                                      flex: 3,
                                      child: Text('البيان',
                                          textAlign: TextAlign.center)),
                                  const Expanded(
                                      flex: 2,
                                      child: Text('المبلغ',
                                          textAlign: TextAlign.center)),
                                  if (!isAnalyticMode)
                                    const Expanded(
                                        flex: 2,
                                        child: Text('الرصيد',
                                            textAlign: TextAlign.center)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: transactions.length,
                                itemBuilder: (context, index) {
                                  final tx = transactions[index];
                                  final amount =
                                      (tx['amount'] as num).toDouble();
                                  final isMomShare = tx['is_mom'] == true;
                                  final isTotal = tx['is_total'] == true;
                                  final isMonthTotal =
                                      tx['is_month_total'] == true;

                                  if (!isAnalyticMode) {
                                    if (tx['type'] == 'month_total') {
                                      // تجاهل الإجمالي الشهري
                                    } else if (tx['type'] == 'expense' ||
                                        tx['type'] == 'mom_share') {
                                      cumulativeBalance += amount;
                                    } else {
                                      cumulativeBalance -= amount;
                                    }
                                  }

                                  return Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                          bottom: BorderSide(
                                              color: Colors.grey.shade300)),
                                      color: isTotal
                                          ? Colors.orange.shade100
                                          : isMonthTotal
                                              ? Colors.purple.shade50
                                              : isMomShare
                                                  ? Colors.blue.shade50
                                                  : tx['type'] == 'expense'
                                                      ? Colors.red.shade50
                                                      : Colors.green.shade50,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            (tx['date'] is String &&
                                                    (tx['date'] as String)
                                                            .length >
                                                        10)
                                                ? (tx['date'] as String)
                                                    .substring(0, 10)
                                                : tx['date'].toString(),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontWeight:
                                                    (isTotal || isMonthTotal)
                                                        ? FontWeight.bold
                                                        : FontWeight.normal),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(tx['description'],
                                              style: TextStyle(
                                                  fontWeight:
                                                      (isTotal || isMonthTotal)
                                                          ? FontWeight.bold
                                                          : FontWeight.normal)),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            isAnalyticMode
                                                ? '${amount.toStringAsFixed(2)}'
                                                : '${amount.toStringAsFixed(2)}',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontWeight:
                                                    (isTotal || isMonthTotal)
                                                        ? FontWeight.bold
                                                        : FontWeight.normal),
                                          ),
                                        ),
                                        if (!isAnalyticMode)
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                                cumulativeBalance
                                                    .toStringAsFixed(2),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (isAnalyticMode && transactions.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                color: Colors.orange.shade100,
                                child: Row(
                                  children: [
                                    const Text('الإجمالي الكلي: ',
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold)),
                                    Text('${reportTotal.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
