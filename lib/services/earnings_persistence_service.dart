import 'dart:convert';
import 'package:shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/user_earnings.dart';

class EarningsPersistenceService {
  static const String _dbName = 'earnings.db';
  static const String _lastSyncKey = 'last_sync_timestamp';
  static const String _pendingChangesKey = 'pending_changes';
  
  late Database _db;
  final SharedPreferences _prefs;

  EarningsPersistenceService(this._prefs);

  Future<void> initialize() async {
    // Initialize SQLite database
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            timestamp INTEGER NOT NULL,
            status TEXT NOT NULL,
            source TEXT,
            destination TEXT,
            metadata TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE pending_changes (
            id TEXT PRIMARY KEY,
            operation TEXT NOT NULL,
            data TEXT NOT NULL,
            timestamp INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> saveTransaction(Transaction transaction) async {
    await _db.insert(
      'transactions',
      {
        'id': transaction.id,
        'type': transaction.type.toString(),
        'amount': transaction.amount,
        'timestamp': transaction.timestamp.millisecondsSinceEpoch,
        'status': transaction.status,
        'source': transaction.source,
        'destination': transaction.destination,
        'metadata': jsonEncode(transaction.metadata),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Track pending change for sync
    await _trackPendingChange('save', transaction);
  }

  Future<List<Transaction>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
    TransactionType? type,
    String? status,
  }) async {
    String query = 'SELECT * FROM transactions WHERE 1=1';
    List<dynamic> args = [];

    if (startDate != null) {
      query += ' AND timestamp >= ?';
      args.add(startDate.millisecondsSinceEpoch);
    }

    if (endDate != null) {
      query += ' AND timestamp <= ?';
      args.add(endDate.millisecondsSinceEpoch);
    }

    if (type != null) {
      query += ' AND type = ?';
      args.add(type.toString());
    }

    if (status != null) {
      query += ' AND status = ?';
      args.add(status);
    }

    query += ' ORDER BY timestamp DESC';

    final List<Map<String, dynamic>> maps = await _db.rawQuery(query, args);

    return List.generate(maps.length, (i) {
      return Transaction(
        id: maps[i]['id'],
        type: TransactionType.values.firstWhere(
          (e) => e.toString() == maps[i]['type'],
        ),
        amount: maps[i]['amount'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(maps[i]['timestamp']),
        status: maps[i]['status'],
        source: maps[i]['source'],
        destination: maps[i]['destination'],
        metadata: jsonDecode(maps[i]['metadata']),
      );
    });
  }

  Future<void> updateTransactionStatus(String id, String status) async {
    await _db.update(
      'transactions',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );

    // Track status update for sync
    await _trackPendingChange('update_status', {'id': id, 'status': status});
  }

  Future<void> deleteTransaction(String id) async {
    await _db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );

    // Track deletion for sync
    await _trackPendingChange('delete', {'id': id});
  }

  Future<void> _trackPendingChange(String operation, dynamic data) async {
    await _db.insert(
      'pending_changes',
      {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'operation': operation,
        'data': jsonEncode(data),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getPendingChanges() async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'pending_changes',
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) {
      return {
        'id': map['id'],
        'operation': map['operation'],
        'data': jsonDecode(map['data']),
        'timestamp': DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      };
    }).toList();
  }

  Future<void> clearPendingChanges(List<String> ids) async {
    await _db.delete(
      'pending_changes',
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<void> setLastSyncTimestamp(DateTime timestamp) async {
    await _prefs.setInt(_lastSyncKey, timestamp.millisecondsSinceEpoch);
  }

  DateTime? getLastSyncTimestamp() {
    final timestamp = _prefs.getInt(_lastSyncKey);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> clearAllData() async {
    await _db.delete('transactions');
    await _db.delete('pending_changes');
    await _prefs.remove(_lastSyncKey);
  }

  Stream<List<Transaction>> watchTransactions({
    DateTime? startDate,
    DateTime? endDate,
    TransactionType? type,
    String? status,
  }) async* {
    while (true) {
      yield await getTransactions(
        startDate: startDate,
        endDate: endDate,
        type: type,
        status: status,
      );
      await Future.delayed(Duration(seconds: 1));
    }
  }

  Future<Map<String, double>> getEarningsSummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final query = '''
      SELECT 
        SUM(CASE WHEN type = ? AND status = 'completed' THEN amount ELSE 0 END) as earned,
        SUM(CASE WHEN type = ? AND status = 'completed' THEN amount ELSE 0 END) as withdrawn,
        SUM(CASE WHEN status = 'pending' THEN amount ELSE 0 END) as pending
      FROM transactions
      WHERE 1=1
    ''';

    List<dynamic> args = [
      TransactionType.earned.toString(),
      TransactionType.withdrawal.toString(),
    ];

    String dateFilter = '';
    if (startDate != null) {
      dateFilter += ' AND timestamp >= ?';
      args.add(startDate.millisecondsSinceEpoch);
    }
    if (endDate != null) {
      dateFilter += ' AND timestamp <= ?';
      args.add(endDate.millisecondsSinceEpoch);
    }

    final result = await _db.rawQuery(query + dateFilter, args);
    
    return {
      'earned': result.first['earned'] as double? ?? 0.0,
      'withdrawn': result.first['withdrawn'] as double? ?? 0.0,
      'pending': result.first['pending'] as double? ?? 0.0,
    };
  }
}