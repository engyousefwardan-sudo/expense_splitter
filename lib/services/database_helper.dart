import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'expense_splitter.db');

    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE beneficiaries (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE items (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category_id TEXT,
        usage_count INTEGER DEFAULT 0,
        created_at TEXT,
        UNIQUE(name),
        FOREIGN KEY (category_id) REFERENCES categories(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE distribution_rules (
        id TEXT PRIMARY KEY,
        beneficiary_id TEXT,
        target_beneficiary_id TEXT,
        percentage REAL,
        created_at TEXT,
        FOREIGN KEY (beneficiary_id) REFERENCES beneficiaries(id),
        FOREIGN KEY (target_beneficiary_id) REFERENCES beneficiaries(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE invoices (
        id TEXT PRIMARY KEY,
        date TEXT,
        notes TEXT,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE invoice_items (
        id TEXT PRIMARY KEY,
        invoice_id TEXT,
        item_id TEXT,
        quantity REAL,
        unit_price REAL,
        total REAL,
        original_beneficiary_id TEXT,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT,
        FOREIGN KEY (invoice_id) REFERENCES invoices(id),
        FOREIGN KEY (item_id) REFERENCES items(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE invoice_item_allocations (
        id TEXT PRIMARY KEY,
        invoice_item_id TEXT,
        beneficiary_id TEXT,
        amount REAL,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT,
        FOREIGN KEY (invoice_item_id) REFERENCES invoice_items(id),
        FOREIGN KEY (beneficiary_id) REFERENCES beneficiaries(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE invoice_item_tags (
        invoice_item_id TEXT,
        tag_id TEXT,
        PRIMARY KEY (invoice_item_id, tag_id),
        FOREIGN KEY (invoice_item_id) REFERENCES invoice_items(id),
        FOREIGN KEY (tag_id) REFERENCES tags(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        payer_id TEXT,
        total_amount REAL,
        date TEXT,
        notes TEXT,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT,
        FOREIGN KEY (payer_id) REFERENCES beneficiaries(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE payment_allocations (
        id TEXT PRIMARY KEY,
        payment_id TEXT,
        beneficiary_id TEXT,
        amount REAL,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT,
        FOREIGN KEY (payment_id) REFERENCES payments(id),
        FOREIGN KEY (beneficiary_id) REFERENCES beneficiaries(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE shared_report_links (
        id TEXT PRIMARY KEY,
        token TEXT NOT NULL UNIQUE,
        pin_code TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db
          .execute('ALTER TABLE invoice_items ADD COLUMN total REAL DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS shared_report_links (
          id TEXT PRIMARY KEY,
          token TEXT NOT NULL UNIQUE,
          pin_code TEXT NOT NULL,
          is_active INTEGER DEFAULT 1,
          created_at TEXT
        )
      ''');
    }
  }

  // دوال مساعدة
  Future<void> insertBeneficiary(Map<String, dynamic> beneficiary) async {
    final db = await database;
    await db.insert('beneficiaries', beneficiary,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertCategory(Map<String, dynamic> category) async {
    final db = await database;
    await db.insert('categories', category,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertItem(Map<String, dynamic> item) async {
    final db = await database;
    await db.insert('items', item,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertInvoice(Map<String, dynamic> invoice) async {
    final db = await database;
    await db.insert('invoices', invoice,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertInvoiceItem(Map<String, dynamic> item) async {
    final db = await database;
    await db.insert('invoice_items', item,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertInvoiceItemAllocation(Map<String, dynamic> alloc) async {
    final db = await database;
    await db.insert('invoice_item_allocations', alloc,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertPayment(Map<String, dynamic> payment) async {
    final db = await database;
    await db.insert('payments', payment,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertPaymentAllocation(Map<String, dynamic> alloc) async {
    final db = await database;
    await db.insert('payment_allocations', alloc,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveInvoiceLocally(
      Map<String, dynamic> invoice,
      List<Map<String, dynamic>> items,
      List<Map<String, dynamic>> allocations) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('invoices', invoice);
      for (var item in items) {
        await txn.insert('invoice_items', item);
      }
      for (var alloc in allocations) {
        await txn.insert('invoice_item_allocations', alloc);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getUnsyncedInvoices() async {
    final db = await database;
    return await db.query('invoices', where: 'is_synced = ?', whereArgs: [0]);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedItems(String invoiceId) async {
    final db = await database;
    return await db.query('invoice_items',
        where: 'invoice_id = ?', whereArgs: [invoiceId]);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedAllocations(
      String itemId) async {
    final db = await database;
    return await db.query('invoice_item_allocations',
        where: 'invoice_item_id = ?', whereArgs: [itemId]);
  }

  Future<void> markInvoiceAsSynced(String invoiceId) async {
    final db = await database;
    await db.update('invoices', {'is_synced': 1},
        where: 'id = ?', whereArgs: [invoiceId]);
    await db.update('invoice_items', {'is_synced': 1},
        where: 'invoice_id = ?', whereArgs: [invoiceId]);
    final items = await db.query('invoice_items',
        columns: ['id'], where: 'invoice_id = ?', whereArgs: [invoiceId]);
    for (var item in items) {
      await db.update('invoice_item_allocations', {'is_synced': 1},
          where: 'invoice_item_id = ?', whereArgs: [item['id']]);
    }
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      final tables = [
        'invoice_item_tags',
        'invoice_item_allocations',
        'invoice_items',
        'invoices',
        'payment_allocations',
        'payments',
        'distribution_rules',
        'tags',
        'items',
        'categories',
        'beneficiaries',
        'settings',
        'shared_report_links'
      ];
      for (var table in tables) {
        await txn.delete(table);
      }
    });
  }
}
