import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import '../../lib/services/earnings_persistence_service.dart';
import '../../lib/models/user_earnings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EarningsPersistenceService Tests', () {
    late Database db;
    late SharedPreferences prefs;
    late EarningsPersistenceService service;
    late String tempDbPath;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // Create a temporary database for testing
      tempDbPath = path.join(await getDatabasesPath(), 'test_earnings.db');
      db = await openDatabase(
        tempDbPath,
        version: 1,
        onCreate: (db, version) async {
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

      // Mock SharedPreferences
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();

      service = EarningsPersistenceService(prefs);
      await service.initialize();
    });

    tearDown(() async {
      await db.close();
      await deleteDatabase(tempDbPath);
    });

    test('saves and retrieves transactions correctly', () async {
      final transaction = Transaction(
        id: '1',
        type: TransactionType.earned,
        amount: 100.0,
        timestamp: DateTime.now(),
        status: 'completed',
        source: 'Test Source',
        destination: null,
        metadata: {'test': 'data'},
      );

      await service.saveTransaction(transaction);

      final retrievedTransactions = await service.getTransactions();
      expect(retrievedTransactions.length, 1);
      expect(retrievedTransactions.first.id, transaction.id);
      expect(retrievedTransactions.first.amount, transaction.amount);
      expect(retrievedTransactions.first.type, transaction.type);
      expect(retrievedTransactions.first.metadata, transaction.metadata);
    });

    test('updates transaction status correctly', () async {
      final transaction = Transaction(
        id: '1',
        type: TransactionType.withdrawal,
        amount: 50.0,
        timestamp: DateTime.now(),
        status: 'pending',
        source: null,
        destination: 'Test Destination',
        metadata: {},
      );

      await service.saveTransaction(transaction);
      await service.updateTransactionStatus(transaction.id, 'completed');

      final retrievedTransactions = await service.getTransactions();
      expect(retrievedTransactions.first.status, 'completed');
    });

    test('filters transactions correctly', () async {
      final now = DateTime.now();
      final transactions = [
        Transaction(
          id: '1',
          type: TransactionType.earned,
          amount: 100.0,
          timestamp: now,
          status: 'completed',
          source: 'Source 1',
          destination: null,
          metadata: {},
        ),
        Transaction(
          id: '2',
          type: TransactionType.withdrawal,
          amount: 50.0,
          timestamp: now.subtract(Duration(days: 1)),
          status: 'pending',
          source: null,
          destination: 'Destination 1',
          metadata: {},
        ),
      ];

      for (final tx in transactions) {
        await service.saveTransaction(tx);
      }

      // Test type filter
      final earnedTransactions = await service.getTransactions(
        type: TransactionType.earned,
      );
      expect(earnedTransactions.length, 1);
      expect(earnedTransactions.first.id, '1');

      // Test status filter
      final pendingTransactions = await service.getTransactions(
        status: 'pending',
      );
      expect(pendingTransactions.length, 1);
      expect(pendingTransactions.first.id, '2');

      // Test date filter
      final recentTransactions = await service.getTransactions(
        startDate: now.subtract(Duration(hours: 12)),
      );
      expect(recentTransactions.length, 1);
      expect(recentTransactions.first.id, '1');
    });

    test('tracks pending changes correctly', () async {
      final transaction = Transaction(
        id: '1',
        type: TransactionType.earned,
        amount: 75.0,
        timestamp: DateTime.now(),
        status: 'completed',
        source: 'Test Source',
        destination: null,
        metadata: {},
      );

      await service.saveTransaction(transaction);
      final pendingChanges = await service.getPendingChanges();

      expect(pendingChanges.length, 1);
      expect(pendingChanges.first['operation'], 'save');
      expect(pendingChanges.first['data']['id'], transaction.id);
    });

    test('clears pending changes correctly', () async {
      final transaction = Transaction(
        id: '1',
        type: TransactionType.earned,
        amount: 75.0,
        timestamp: DateTime.now(),
        status: 'completed',
        source: 'Test Source',
        destination: null,
        metadata: {},
      );

      await service.saveTransaction(transaction);
      final pendingChanges = await service.getPendingChanges();
      await service.clearPendingChanges([pendingChanges.first['id']]);

      final remainingChanges = await service.getPendingChanges();
      expect(remainingChanges.isEmpty, true);
    });

    test('manages sync timestamp correctly', () async {
      final timestamp = DateTime.now();
      await service.setLastSyncTimestamp(timestamp);

      final retrievedTimestamp = service.getLastSyncTimestamp();
      expect(
        retrievedTimestamp?.millisecondsSinceEpoch,
        timestamp.millisecondsSinceEpoch,
      );
    });

    test('calculates earnings summary correctly', () async {
      final now = DateTime.now();
      final transactions = [
        Transaction(
          id: '1',
          type: TransactionType.earned,
          amount: 100.0,
          timestamp: now,
          status: 'completed',
          source: 'Source 1',
          destination: null,
          metadata: {},
        ),
        Transaction(
          id: '2',
          type: TransactionType.withdrawal,
          amount: 50.0,
          timestamp: now,
          status: 'completed',
          source: null,
          destination: 'Destination 1',
          metadata: {},
        ),
        Transaction(
          id: '3',
          type: TransactionType.earned,
          amount: 75.0,
          timestamp: now,
          status: 'pending',
          source: 'Source 2',
          destination: null,
          metadata: {},
        ),
      ];

      for (final tx in transactions) {
        await service.saveTransaction(tx);
      }

      final summary = await service.getEarningsSummary();
      expect(summary['earned'], 100.0);
      expect(summary['withdrawn'], 50.0);
      expect(summary['pending'], 75.0);
    });

    test('handles data deletion correctly', () async {
      final transaction = Transaction(
        id: '1',
        type: TransactionType.earned,
        amount: 100.0,
        timestamp: DateTime.now(),
        status: 'completed',
        source: 'Test Source',
        destination: null,
        metadata: {},
      );

      await service.saveTransaction(transaction);
      await service.clearAllData();

      final transactions = await service.getTransactions();
      expect(transactions.isEmpty, true);

      final pendingChanges = await service.getPendingChanges();
      expect(pendingChanges.isEmpty, true);

      final lastSync = service.getLastSyncTimestamp();
      expect(lastSync, null);
    });

    test('streams transaction updates correctly', () async {
      final stream = service.watchTransactions();
      final streamData = stream.take(2).toList();

      // Add transactions while listening
      await service.saveTransaction(
        Transaction(
          id: '1',
          type: TransactionType.earned,
          amount: 100.0,
          timestamp: DateTime.now(),
          status: 'completed',
          source: 'Test Source',
          destination: null,
          metadata: {},
        ),
      );

      final updates = await streamData;
      expect(updates.length, 2);
      expect(updates.first.isEmpty, true);
      expect(updates.last.length, 1);
      expect(updates.last.first.id, '1');
    });
  });
}