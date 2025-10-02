import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../lib/services/earnings_persistence_service.dart';
import '../../lib/models/user_earnings.dart';
import '../../lib/models/user_payment_preferences.dart';
import '../../lib/widgets/earnings_chart.dart';
import '../../lib/widgets/transaction_list.dart';
import '../../lib/widgets/withdraw_dialog.dart';

void main() {
  group('Earnings Management Integration Tests', () {
    late EarningsPersistenceService persistenceService;
    late Widget testApp;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      persistenceService = EarningsPersistenceService(prefs);
      await persistenceService.initialize();

      // Sample payment methods for testing
      final paymentMethods = [
        PaymentMethod(
          id: '1',
          type: 'bank',
          name: 'Test Bank Account',
          details: {'accountNumber': '****1234'},
        ),
      ];

      testApp = MultiProvider(
        providers: [
          Provider<EarningsPersistenceService>.value(
            value: persistenceService,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  flex: 2,
                  child: EarningsChart(
                    data: [],
                    timeRange: 'week',
                    onSelectDate: (_) {},
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: TransactionList(
                    transactions: [],
                    onTapTransaction: (_) {},
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Withdrawal button implementation
                  },
                  child: Text('Withdraw Earnings'),
                ),
              ],
            ),
          ),
        ),
      );
    });

    testWidgets('complete earnings management flow', (WidgetTester tester) async {
      await tester.pumpWidget(testApp);

      // 1. Verify initial empty state
      expect(find.text('No transactions found'), findsOneWidget);
      expect(find.byType(EarningsChart), findsOneWidget);
      expect(find.byType(TransactionList), findsOneWidget);

      // 2. Add a test earning transaction
      final earning = Transaction(
        id: '1',
        type: TransactionType.earned,
        amount: 100.0,
        timestamp: DateTime.now(),
        status: 'completed',
        source: 'Test Project',
        destination: null,
        metadata: {},
      );

      await persistenceService.saveTransaction(earning);
      await tester.pump();

      // 3. Verify earning is displayed
      expect(find.text('Test Project'), findsOneWidget);
      expect(find.text('\$100.00'), findsOneWidget);

      // 4. Initiate withdrawal
      await tester.tap(find.text('Withdraw Earnings'));
      await tester.pumpAndSettle();

      // 5. Verify withdrawal dialog
      expect(find.text('Withdraw Earnings'), findsOneWidget);
      expect(find.text('Available Balance: \$100.00'), findsOneWidget);

      // 6. Enter withdrawal amount
      await tester.enterText(
        find.byType(TextFormField),
        '50.00',
      );
      await tester.pump();

      // 7. Submit withdrawal
      await tester.tap(find.text('Withdraw'));
      await tester.pump();

      // 8. Verify new transaction in list
      final withdrawalTx = await persistenceService.getTransactions(
        type: TransactionType.withdrawal,
      );
      expect(withdrawalTx.length, 1);
      expect(withdrawalTx.first.amount, 50.0);

      // 9. Verify updated balance
      final summary = await persistenceService.getEarningsSummary();
      expect(summary['earned'], 100.0);
      expect(summary['withdrawn'], 50.0);

      // 10. Test filtering
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Withdrawn'));
      await tester.pumpAndSettle();

      expect(find.text('Test Project'), findsNothing);
      expect(find.text('Bank Account'), findsOneWidget);

      // 11. Test transaction selection
      await tester.tap(find.text('Bank Account'));
      await tester.pump();

      // 12. Verify persistence across sessions
      await persistenceService.setLastSyncTimestamp(DateTime.now());
      final lastSync = persistenceService.getLastSyncTimestamp();
      expect(lastSync, isNotNull);

      final pendingChanges = await persistenceService.getPendingChanges();
      expect(pendingChanges.isNotEmpty, true);

      // 13. Test error handling
      await tester.tap(find.text('Withdraw Earnings'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField),
        '1000.00',
      );
      await tester.pump();

      await tester.tap(find.text('Withdraw'));
      await tester.pump();

      expect(find.text('Amount exceeds available balance'), findsOneWidget);

      // 14. Clean up
      await persistenceService.clearAllData();
      await tester.pump();

      expect(find.text('No transactions found'), findsOneWidget);
    });

    testWidgets('handles network connectivity changes', (WidgetTester tester) async {
      await tester.pumpWidget(testApp);

      // 1. Add offline transaction
      final offlineEarning = Transaction(
        id: '1',
        type: TransactionType.earned,
        amount: 75.0,
        timestamp: DateTime.now(),
        status: 'pending',
        source: 'Offline Project',
        destination: null,
        metadata: {'offline': true},
      );

      await persistenceService.saveTransaction(offlineEarning);
      await tester.pump();

      // 2. Verify pending state
      expect(find.text('Offline Project'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);

      // 3. Simulate sync
      await persistenceService.updateTransactionStatus('1', 'completed');
      await tester.pump();

      expect(find.text('COMPLETED'), findsOneWidget);

      // 4. Verify pending changes tracked
      final pendingChanges = await persistenceService.getPendingChanges();
      expect(pendingChanges.length, 2); // Save + Status update

      // 5. Clear pending changes
      await persistenceService.clearPendingChanges(
        pendingChanges.map((c) => c['id'] as String).toList(),
      );
      
      final remainingChanges = await persistenceService.getPendingChanges();
      expect(remainingChanges.isEmpty, true);
    });

    testWidgets('data persistence and recovery', (WidgetTester tester) async {
      await tester.pumpWidget(testApp);

      // 1. Add multiple transactions
      final transactions = [
        Transaction(
          id: '1',
          type: TransactionType.earned,
          amount: 100.0,
          timestamp: DateTime.now(),
          status: 'completed',
          source: 'Project A',
          metadata: {},
        ),
        Transaction(
          id: '2',
          type: TransactionType.earned,
          amount: 150.0,
          timestamp: DateTime.now(),
          status: 'completed',
          source: 'Project B',
          metadata: {},
        ),
        Transaction(
          id: '3',
          type: TransactionType.withdrawal,
          amount: 75.0,
          timestamp: DateTime.now(),
          status: 'pending',
          destination: 'Bank Account',
          metadata: {},
        ),
      ];

      for (final tx in transactions) {
        await persistenceService.saveTransaction(tx);
      }
      await tester.pump();

      // 2. Verify transactions displayed
      expect(find.text('Project A'), findsOneWidget);
      expect(find.text('Project B'), findsOneWidget);
      expect(find.text('Bank Account'), findsOneWidget);

      // 3. Simulate app restart
      await tester.pumpWidget(testApp);

      // 4. Verify data persisted
      final savedTransactions = await persistenceService.getTransactions();
      expect(savedTransactions.length, 3);

      // 5. Verify summary calculations
      final summary = await persistenceService.getEarningsSummary();
      expect(summary['earned'], 250.0);
      expect(summary['pending'], 75.0);

      // 6. Test date range filtering
      final now = DateTime.now();
      final recentTransactions = await persistenceService.getTransactions(
        startDate: now.subtract(Duration(minutes: 1)),
        endDate: now.add(Duration(minutes: 1)),
      );
      expect(recentTransactions.length, 3);

      // 7. Verify stream updates
      final streamController = persistenceService.watchTransactions();
      final subscription = streamController.listen(
        expectAsync1(
          (transactions) {
            expect(transactions.length, greaterThanOrEqualTo(3));
          },
          count: 1,
        ),
      );

      await subscription.cancel();
    });
  });
}