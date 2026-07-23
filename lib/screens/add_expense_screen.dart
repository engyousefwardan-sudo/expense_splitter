import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/database_helper.dart';

class ExpenseRow {
  String? selectedItemId;
  String? selectedItemName;
  String? selectedBeneficiaryId;
  double quantity = 1;
  double unitPrice = 0;
  List<String> selectedTagIds = [];

  double get total => quantity * unitPrice;
}

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => AddExpenseScreenState();
}

class AddExpenseScreenState extends State<AddExpenseScreen> {
  final supabase = Supabase.instance.client;
  final _uuid = const Uuid();
  final dbHelper = DatabaseHelper();

  final List<ExpenseRow> rows = [];

  List<Map<String, dynamic>> items = [];
  List<Map<String, dynamic>> beneficiaries = [];
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> tags = [];
  bool isLoading = true;
  bool hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      if (!kIsWeb) {
        final db = await dbHelper.database;
        final localItems = await db.query('items', orderBy: 'usage_count DESC');
        final localBen = await db.query('beneficiaries');
        final localCat = await db.query('categories');
        final localTags = await db.query('tags');

        if (localItems.isNotEmpty) {
          setState(() {
            items = localItems;
            beneficiaries = localBen;
            categories = localCat;
            tags = localTags;
            isLoading = false;
          });
          return;
        }
      }

      final itemsResponse = await supabase
          .from('items')
          .select('id, name, category_id')
          .order('usage_count', ascending: false);
      final benResponse =
          await supabase.from('beneficiaries').select('id, name');
      final catResponse = await supabase.from('categories').select('id, name');
      final tagsResponse = await supabase.from('tags').select('id, name');

      setState(() {
        items = List<Map<String, dynamic>>.from(itemsResponse);
        beneficiaries = List<Map<String, dynamic>>.from(benResponse);
        categories = List<Map<String, dynamic>>.from(catResponse);
        tags = List<Map<String, dynamic>>.from(tagsResponse);
        isLoading = false;
      });
    } catch (e) {
      debugPrint('خطأ في تحميل البيانات: $e');
      setState(() => isLoading = false);
    }
  }

  void addRow() {
    setState(() {
      rows.add(ExpenseRow());
      hasUnsavedChanges = true;
    });
  }

  void removeRow(int index) {
    setState(() {
      rows.removeAt(index);
    });
  }

  void clearRows() {
    setState(() {
      rows.clear();
    });
  }

  void setUnsaved(bool val) {
    setState(() {
      hasUnsavedChanges = val;
    });
  }

  double get totalInvoice => rows.fold(0, (sum, row) => sum + row.total);

  Future<bool> _isConnected() async {
    if (kIsWeb) return true;
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<bool> saveInvoice() async {
    for (var row in rows) {
      if (row.selectedItemId == null || row.selectedBeneficiaryId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب اختيار الصنف والمستفيد لكل بند')),
        );
        return false;
      }
    }

    for (var row in rows) {
      if (row.unitPrice <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب إدخال سعر لكل بند')),
        );
        return false;
      }
    }

    try {
      final invoiceId = _uuid.v4();
      final dateStr = DateTime.now().toIso8601String().split('T').first;
      final now = DateTime.now().toIso8601String();

      final Set<String> usedItemIds = {};
      final List<Map<String, dynamic>> itemsList = [];
      final List<Map<String, dynamic>> allocsList = [];

      for (var row in rows) {
        usedItemIds.add(row.selectedItemId!);
        final itemId = _uuid.v4();

        itemsList.add({
          'id': itemId,
          'invoice_id': invoiceId,
          'item_id': row.selectedItemId,
          'quantity': row.quantity,
          'unit_price': row.unitPrice,
          'total': row.total,
          'original_beneficiary_id': row.selectedBeneficiaryId,
          'is_synced': 0,
          'created_at': now,
        });

        List rules = [];
        // جرب السحابة أولاً إذا كان متصلاً
        final connected = await _isConnected();
        if (connected) {
          try {
            rules = await supabase
                .from('distribution_rules')
                .select('target_beneficiary_id, percentage')
                .eq('beneficiary_id', row.selectedBeneficiaryId!);
          } catch (_) {
            // إذا فشلت السحابة، استخدم المحلي
          }
        }
        // إذا لم تكن هناك نتائج من السحابة أو غير متصل، استخدم المحلي
        if (rules.isEmpty && !kIsWeb) {
          final db = await dbHelper.database;
          rules = await db.query('distribution_rules',
              where: 'beneficiary_id = ?',
              whereArgs: [row.selectedBeneficiaryId]);
        }
        if (rules.isNotEmpty) {
          for (var rule in rules) {
            final targetId = rule['target_beneficiary_id'] as String;
            final percentage = (rule['percentage'] as num).toDouble();
            final amount = row.total * (percentage / 100.0);
            allocsList.add({
              'id': _uuid.v4(),
              'invoice_item_id': itemId,
              'beneficiary_id': targetId,
              'amount': amount,
              'is_synced': 0,
              'created_at': now,
            });
          }
        } else {
          allocsList.add({
            'id': _uuid.v4(),
            'invoice_item_id': itemId,
            'beneficiary_id': row.selectedBeneficiaryId,
            'amount': row.total,
            'is_synced': 0,
            'created_at': now,
          });
        }
      }

      // حفظ محلياً
      if (!kIsWeb) {
        await dbHelper.saveInvoiceLocally(
          {
            'id': invoiceId,
            'date': dateStr,
            'is_synced': 0,
            'created_at': now,
          },
          itemsList,
          allocsList,
        );
      }

      // محاولة الرفع للسحابة
      bool syncedToCloud = false;
      if (await _isConnected()) {
        try {
          await supabase.from('invoices').insert({
            'id': invoiceId,
            'date': dateStr,
          });

          for (var item in itemsList) {
            await supabase.from('invoice_items').insert({
              'id': item['id'],
              'invoice_id': item['invoice_id'],
              'item_id': item['item_id'],
              'quantity': item['quantity'],
              'unit_price': item['unit_price'],
              'original_beneficiary_id': item['original_beneficiary_id'],
            });

            for (var alloc in allocsList) {
              if (alloc['invoice_item_id'] == item['id']) {
                await supabase.from('invoice_item_allocations').insert({
                  'id': alloc['id'],
                  'invoice_item_id': alloc['invoice_item_id'],
                  'beneficiary_id': alloc['beneficiary_id'],
                  'amount': alloc['amount'],
                });
              }
            }
          }

          for (var itemId in usedItemIds) {
            await supabase.rpc('increment_usage', params: {'item_id': itemId});
          }

          syncedToCloud = true;

          if (!kIsWeb) {
            await dbHelper.markInvoiceAsSynced(invoiceId);
          }
        } catch (e) {
          debugPrint('فشل الرفع للسحابة: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(syncedToCloud
                ? 'تم حفظ الفاتورة ورفعها للسحابة'
                : 'تم حفظ الفاتورة محلياً (ستتم المزامنة لاحقاً)'),
          ),
        );
      }
      hasUnsavedChanges = false;
      clearRows();
      loadData();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في الحفظ: $e')),
        );
      }
      return false;
    }
  }

  // ---------- الوسوم ----------
  Future<void> showTagSelectionDialog(int rowIndex) async {
    final row = rows[rowIndex];
    List<String> tempSelected = List<String>.from(row.selectedTagIds);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('اختيار الوسوم'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...tags.map((tag) {
                  final tagId = tag['id'] as String;
                  final tagName = tag['name'] as String;
                  final isChecked = tempSelected.contains(tagId);
                  return CheckboxListTile(
                    value: isChecked,
                    title: Text(tagName),
                    onChanged: (bool? checked) {
                      setDialogState(() {
                        if (checked == true) {
                          tempSelected.add(tagId);
                        } else {
                          tempSelected.remove(tagId);
                        }
                      });
                    },
                  );
                }).toList(),
                const Divider(),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة وسم جديد'),
                  onPressed: () async {
                    final newTagName = await showDialog<String>(
                      context: ctx,
                      builder: (ctx2) {
                        final tagController = TextEditingController();
                        return AlertDialog(
                          title: const Text('إضافة وسم جديد'),
                          content: TextField(
                            controller: tagController,
                            decoration:
                                const InputDecoration(labelText: 'اسم الوسم'),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx2),
                              child: const Text('إلغاء'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                final name = tagController.text.trim();
                                if (name.isNotEmpty) {
                                  Navigator.pop(ctx2, name);
                                }
                              },
                              child: const Text('حفظ'),
                            ),
                          ],
                        );
                      },
                    );
                    if (newTagName != null && newTagName.isNotEmpty) {
                      try {
                        final tagResponse = await supabase
                            .from('tags')
                            .insert({'name': newTagName})
                            .select('id, name')
                            .single();
                        setState(() {
                          tags.add(Map<String, dynamic>.from(tagResponse));
                        });
                        setDialogState(() {
                          tempSelected.add(tagResponse['id'] as String);
                        });
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('فشل إضافة الوسم: $e')),
                          );
                        }
                      }
                    }
                  },
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
              onPressed: () {
                setState(() {
                  row.selectedTagIds = tempSelected;
                });
                Navigator.pop(ctx);
              },
              child: const Text('موافق'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- إضافة صنف جديد (مع تصنيف ذكي) ----------
  Future<String?> showAddItemDialog() async {
    String newItemName = '';
    String? selectedCategoryId;
    String? selectedCategoryName;
    final nameController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة صنف جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'اسم الصنف'),
              ),
              const SizedBox(height: 12),
              Autocomplete<String>(
                key: ValueKey('cat_dialog_${selectedCategoryName ?? ''}'),
                initialValue:
                    TextEditingValue(text: selectedCategoryName ?? ''),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final input = textEditingValue.text.trim();
                  if (input.isEmpty) return const Iterable<String>.empty();
                  final filtered = categories
                      .where((c) => (c['name'] as String)
                          .toLowerCase()
                          .contains(input.toLowerCase()))
                      .map((c) => c['name'] as String)
                      .toList();

                  bool exactMatch = categories.any((c) =>
                      (c['name'] as String).toLowerCase() ==
                      input.toLowerCase());

                  if (exactMatch) {
                    return filtered;
                  } else {
                    return [...filtered, '➕ إضافة تصنيف جديد'];
                  }
                },
                onSelected: (String selection) async {
                  if (selection == '➕ إضافة تصنيف جديد') {
                    final newCatName = await showDialog<String>(
                      context: ctx,
                      builder: (ctx2) {
                        final catController = TextEditingController();
                        return AlertDialog(
                          title: const Text('إضافة تصنيف جديد'),
                          content: TextField(
                            controller: catController,
                            decoration:
                                const InputDecoration(labelText: 'اسم التصنيف'),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx2),
                              child: const Text('إلغاء'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                final name = catController.text.trim();
                                if (name.isNotEmpty) {
                                  Navigator.pop(ctx2, name);
                                }
                              },
                              child: const Text('حفظ'),
                            ),
                          ],
                        );
                      },
                    );
                    if (newCatName != null && newCatName.isNotEmpty) {
                      try {
                        final catResponse = await supabase
                            .from('categories')
                            .insert({'name': newCatName})
                            .select('id, name')
                            .single();
                        setState(() {
                          categories
                              .add(Map<String, dynamic>.from(catResponse));
                        });
                        setDialogState(() {
                          selectedCategoryId = catResponse['id'] as String;
                          selectedCategoryName = newCatName;
                        });
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('فشل إضافة التصنيف: $e')),
                          );
                        }
                      }
                    } else {
                      setDialogState(() {
                        selectedCategoryId = null;
                        selectedCategoryName = null;
                      });
                    }
                  } else {
                    final cat =
                        categories.firstWhere((c) => c['name'] == selection);
                    setDialogState(() {
                      selectedCategoryId = cat['id'] as String;
                      selectedCategoryName = selection;
                    });
                  }
                },
                fieldViewBuilder: (context, textEditingController, focusNode,
                    onFieldSubmitted) {
                  return TextFormField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'التصنيف',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_drop_down),
                        onPressed: () {
                          _showCategoryMenu(context, textEditingController,
                              (catId, catName) {
                            setDialogState(() {
                              selectedCategoryId = catId;
                              selectedCategoryName = catName;
                            });
                          });
                        },
                      ),
                    ),
                    onFieldSubmitted: (String value) => onFieldSubmitted(),
                  );
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
              onPressed: () {
                newItemName = nameController.text.trim();
                if (newItemName.isEmpty || selectedCategoryId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يجب إدخال الاسم والتصنيف')),
                  );
                  return;
                }
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (newItemName.isNotEmpty && selectedCategoryId != null) {
      try {
        final response = await supabase
            .from('items')
            .insert({
              'name': newItemName,
              'category_id': selectedCategoryId,
              'usage_count': 0,
            })
            .select('id, name, category_id')
            .single();

        setState(() {
          items.add(Map<String, dynamic>.from(response));
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم إضافة الصنف "$newItemName"')),
          );
        }
        return newItemName;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل إضافة الصنف: $e')),
          );
        }
        return null;
      }
    }
    return null;
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

  void _showItemMenu(
      BuildContext context, TextEditingController controller, ExpenseRow row) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset offset = box.localToGlobal(Offset.zero);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(offset.dx, offset.dy + box.size.height,
          offset.dx + box.size.width, offset.dy + box.size.height + 300),
      items: [
        ...items.map((item) {
          final name = item['name'] as String;
          return PopupMenuItem<String>(value: name, child: Text(name));
        }).toList(),
        const PopupMenuItem<String>(
          value: '__new__',
          child: Text('➕ إضافة صنف جديد', style: TextStyle(color: Colors.blue)),
        ),
      ],
    ).then((selected) async {
      if (selected == '__new__') {
        final newItemName = await showAddItemDialog();
        if (newItemName != null) {
          final newItem = items.firstWhere((i) => i['name'] == newItemName);
          setState(() {
            row.selectedItemId = newItem['id'] as String;
            row.selectedItemName = newItemName;
          });
          controller.text = newItemName;
        }
      } else if (selected != null) {
        final item = items.firstWhere((i) => i['name'] == selected);
        setState(() {
          row.selectedItemId = item['id'] as String;
          row.selectedItemName = selected;
        });
        controller.text = selected;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدخال مصروف جديد'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.black),
            tooltip: 'حفظ الفاتورة',
            onPressed: rows.isNotEmpty ? () => saveInvoice() : null,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: rows.isEmpty
                      ? const Center(
                          child: Text(
                            'اضغط على "+" لإضافة بنود',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, index) => buildRow(index),
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[200],
                  child: Row(
                    children: [
                      Text(
                        'الإجمالي: ${totalInvoice.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: addRow,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget buildRow(int index) {
    final row = rows[index];
    final tagCount = row.selectedTagIds.length;
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    Widget fieldsRow = Row(
      children: [
        SizedBox(
          width: isSmallScreen ? 140 : 180,
          child: Autocomplete<String>(
            key: ValueKey('${index}_${row.selectedItemName ?? ''}'),
            initialValue: TextEditingValue(text: row.selectedItemName ?? ''),
            optionsBuilder: (TextEditingValue textEditingValue) {
              final input = textEditingValue.text.trim();
              if (input.isEmpty) return const Iterable<String>.empty();
              final filtered = items
                  .where((i) => (i['name'] as String)
                      .toLowerCase()
                      .contains(input.toLowerCase()))
                  .map((i) => i['name'] as String)
                  .toList();

              bool exactMatch = items.any((i) =>
                  (i['name'] as String).toLowerCase() == input.toLowerCase());

              if (exactMatch) {
                return filtered;
              } else {
                return [...filtered, '➕ إضافة صنف جديد'];
              }
            },
            onSelected: (String selection) async {
              if (selection == '➕ إضافة صنف جديد') {
                final newItemName = await showAddItemDialog();
                if (newItemName != null) {
                  final newItem =
                      items.firstWhere((i) => i['name'] == newItemName);
                  setState(() {
                    row.selectedItemId = newItem['id'] as String;
                    row.selectedItemName = newItemName;
                  });
                } else {
                  setState(() {
                    row.selectedItemId = null;
                    row.selectedItemName = null;
                  });
                }
              } else {
                final item = items.firstWhere((i) => i['name'] == selection);
                setState(() {
                  row.selectedItemId = item['id'] as String;
                  row.selectedItemName = selection;
                });
              }
            },
            fieldViewBuilder:
                (context, textEditingController, focusNode, onFieldSubmitted) {
              focusNode.addListener(() {
                if (!focusNode.hasFocus) {
                  final currentText = textEditingController.text.trim();
                  if (currentText.isNotEmpty) {
                    final exactMatch = items.any((i) =>
                        (i['name'] as String).toLowerCase() ==
                        currentText.toLowerCase());
                    if (!exactMatch && row.selectedItemId != null) {
                      setState(() {
                        row.selectedItemId = null;
                        row.selectedItemName = null;
                      });
                    }
                  }
                }
              });

              return TextFormField(
                controller: textEditingController,
                focusNode: focusNode,
                decoration: InputDecoration(
                  labelText: 'الصنف',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () =>
                        _showItemMenu(context, textEditingController, row),
                  ),
                ),
                onFieldSubmitted: (String value) => onFieldSubmitted(),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: isSmallScreen ? 60 : 80,
          child: TextFormField(
            initialValue: row.quantity.toString(),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'الكمية'),
            onChanged: (val) {
              setState(() {
                row.quantity = double.tryParse(val) ?? 1;
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: isSmallScreen ? 70 : 90,
          child: TextFormField(
            initialValue: row.unitPrice == 0 ? '' : row.unitPrice.toString(),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'السعر'),
            onChanged: (val) {
              setState(() {
                row.unitPrice = double.tryParse(val) ?? 0;
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: isSmallScreen ? 120 : 150,
          child: DropdownButtonFormField<String>(
            value: row.selectedBeneficiaryId,
            decoration: const InputDecoration(labelText: 'المستفيد'),
            items: beneficiaries.map((b) {
              return DropdownMenuItem<String>(
                value: b['id'] as String,
                child: Text(b['name'] as String),
              );
            }).toList(),
            onChanged: (val) {
              setState(() => row.selectedBeneficiaryId = val);
            },
          ),
        ),
        const SizedBox(width: 4),
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.label_outline),
              tooltip: 'الوسوم',
              onPressed: () => showTagSelectionDialog(index),
            ),
            if (tagCount > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    '$tagCount',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 70,
          child: Text(
            row.total.toStringAsFixed(2),
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => removeRow(index),
        ),
      ],
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: fieldsRow,
        ),
      ),
    );
  }
}
