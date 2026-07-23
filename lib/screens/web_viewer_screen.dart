import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WebViewerScreen extends StatefulWidget {
  final String token;
  const WebViewerScreen({super.key, required this.token});

  @override
  State<WebViewerScreen> createState() => _WebViewerScreenState();
}

class _WebViewerScreenState extends State<WebViewerScreen> {
  final _pinController = TextEditingController();
  final supabase = Supabase.instance.client;
  String _message = '';
  bool _isLoading = false;
  bool _isAuthenticated = false;

  // بيانات التقارير
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
  bool isLoadingData = true;

  bool get isAnalyticMode =>
      selectedCategoryId != null ||
      selectedItemId != null ||
      selectedTagId != null;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _verifyPin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _message = 'يجب إدخال 6 أرقام');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final links = await supabase
          .from('shared_report_links')
          .select('pin_code, is_active')
          .eq('token', widget.token)
          .maybeSingle();

      if (links == null) {
        setState(() => _message = 'الرابط غير صالح');
      } else if (links['is_active'] != true) {
        setState(() => _message = 'الرابط غير نشط');
      } else if (links['pin_code'] == pin) {
        setState(() => _isAuthenticated = true);
        await _loadData();
      } else {
        setState(() => _message = 'الرمز السري غير صحيح');
      }
    } catch (e) {
      setState(() => _message = 'خطأ: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadData() async {
    setState(() => isLoadingData = true);
    try {
      final allBen = await supabase.from('beneficiaries').select('id, name');
      final List<Map<String, dynamic>> benList =
          List<Map<String, dynamic>>.from(allBen);
      final filtered = benList.where((b) {
        final name = (b['name'] as String).trim();
        return name == 'عبد' || name == 'الأم';
      }).toList();

      final cats = await supabase.from('categories').select('id, name');
      final allItems =
          await supabase.from('items').select('id, name, category_id');
      final allTags = await supabase.from('tags').select('id, name');

      setState(() {
        beneficiaries = filtered;
        categories = List<Map<String, dynamic>>.from(cats);
        items = List<Map<String, dynamic>>.from(allItems);
        tags = List<Map<String, dynamic>>.from(allTags);

        final abd = filtered.cast<Map<String, dynamic>?>().firstWhere(
              (b) => b != null && (b['name'] as String).trim() == 'عبد',
              orElse: () => null,
            );
        if (abd != null) {
          selectedBeneficiaryId = abd['id'] as String;
          currentBeneficiaryName = abd['name'] as String;
        } else if (filtered.isNotEmpty) {
          selectedBeneficiaryId = filtered.first['id'] as String;
          currentBeneficiaryName = filtered.first['name'] as String;
        }
      });

      await loadTransactions();
    } catch (e) {
      debugPrint('خطأ في تحميل البيانات: $e');
    } finally {
      setState(() => isLoadingData = false);
    }
  }

  void selectBeneficiary(String id, String name) {
    setState(() {
      selectedBeneficiaryId = id;
      currentBeneficiaryName = name;
    });
    loadTransactions();
  }

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

  Future<void> loadTransactions() async {
    if (selectedBeneficiaryId == null) return;
    setState(() => isLoadingData = true);

    try {
      final bool isMom = (currentBeneficiaryName == 'الأم');
      final bool isSon = (currentBeneficiaryName == 'عبد');
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

        final String? origBenId = item['original_beneficiary_id'] as String?;
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
            (prodData?['categories'] as Map<String, dynamic>?)?['name'] ?? '';

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

      // الدفعات
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
            'created_at': DateTime.tryParse(p['created_at'] as String? ?? '') ??
                DateTime.now(),
            'date': pay['date'] as String? ?? '',
            'description': 'دفعة (دافع: $payerName)',
            'type': 'payment',
            'amount': (p['amount'] as num).toDouble(),
            'event_type': 'payment',
          });
        }
      }

      allEvents.sort((a, b) =>
          (a['created_at'] as DateTime).compareTo(b['created_at'] as DateTime));

      // بناء القائمة
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
      setState(() => isLoadingData = false);
    }
  }

  // -------------------- واجهة المستخدم --------------------
  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('تسجيل الدخول')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.lock, size: 64, color: Colors.teal),
                const SizedBox(height: 24),
                const Text('أدخل رمز المشاهدة (6 أرقام)'),
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
                  onPressed: _isLoading ? null : _verifyPin,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text('دخول'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // بعد التوثيق: عرض التقارير
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
          if (beneficiaries.isNotEmpty)
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
                      value: b['id'] as String,
                      child: Text(b['name'] as String));
                }).toList();
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                              initialValue: TextEditingValue(
                                  text: selectedCategoryName ?? ''),
                              optionsBuilder:
                                  (TextEditingValue textEditingValue) {
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
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Autocomplete<String>(
                              key: ValueKey(
                                  'item_filter_${selectedItemName ?? ''}'),
                              initialValue: TextEditingValue(
                                  text: selectedItemName ?? ''),
                              optionsBuilder:
                                  (TextEditingValue textEditingValue) {
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
                                final item = items
                                    .firstWhere((i) => i['name'] == selection);
                                setState(() {
                                  selectedItemId = item['id'] as String;
                                  selectedItemName = selection;
                                });
                                applyFilters();
                              },
                              fieldViewBuilder: (context, textEditingController,
                                  focusNode, onFieldSubmitted) {
                                return TextFormField(
                                  controller: textEditingController,
                                  focusNode: focusNode,
                                  decoration: InputDecoration(
                                    labelText: 'الصنف',
                                    contentPadding: EdgeInsets.zero,
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.arrow_drop_down),
                                      onPressed: () {
                                        _showItemMenu(
                                            context, textEditingController,
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
                  child: transactions.isEmpty
                      ? const Center(child: Text('لا توجد معاملات'))
                      : Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            children: [
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
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
                                        // تجاهل الإجمالي الشهري، فهو ملخص فقط
                                      } else if (tx['type'] == 'expense' || tx['type'] == 'mom_share') {
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
                                                    fontWeight: (isTotal ||
                                                            isMonthTotal)
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
}
