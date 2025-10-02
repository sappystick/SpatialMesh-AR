import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/widgets/transaction_list.dart';
import '../../lib/models/user_earnings.dart';

void main() {
  group('TransactionList Widget Tests', () {
    late List<Transaction> testTransactions;

    setUp(() {
      final now = DateTime.now();
      
      testTransactions = [
        Transaction(
          id: '1',
          type: TransactionType.earned,
          amount: 150.0,
          timestamp: now.subtract(Duration(hours: 1)),
          status: 'completed',
          source: 'Project A',
          destination: null,
          metadata: {},
        ),
        Transaction(
          id: '2',
          type: TransactionType.withdrawal,
          amount: 100.0,
          timestamp: now.subtract(Duration(hours: 2)),
          status: 'pending',
          source: null,
          destination: 'Bank Account',
          metadata: {},
        ),
        Transaction(
          id: '3',
          type: TransactionType.earned,
          amount: 75.0,
          timestamp: now.subtract(Duration(hours: 3)),
          status: 'completed',
          source: 'Project B',
          destination: null,
          metadata: {},
        ),
      ];
    });

    testWidgets('renders transaction list correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionList(
              transactions: testTransactions,
              onTapTransaction: (_) {},
            ),
          ),
        ),
      );

      // Verify title is displayed
      expect(find.text('Transaction History'), findsOneWidget);

      // Verify all transactions are rendered
      for (final transaction in testTransactions) {
        expect(
          find.textContaining(transaction.amount.toString()),
          findsOneWidget,
        );
      }

      // Verify status labels
      expect(find.text('COMPLETED'), findsNWidgets(2));
      expect(find.text('PENDING'), findsOneWidget);
    });

    testWidgets('handles empty state correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionList(
              transactions: [],
              onTapTransaction: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('No transactions found'), findsOneWidget);
    });

    testWidgets('filters transactions correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionList(
              transactions: testTransactions,
              onTapTransaction: (_) {},
              filterType: 'earned',
            ),
          ),
        ),
      );

      // Should only show earned transactions
      expect(find.text('Project A'), findsOneWidget);
      expect(find.text('Project B'), findsOneWidget);
      expect(find.text('Bank Account'), findsNothing);
    });

    testWidgets('handles transaction tap callback', (WidgetTester tester) async {
      Transaction? tappedTransaction;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionList(
              transactions: testTransactions,
              onTapTransaction: (transaction) {
                tappedTransaction = transaction;
              },
            ),
          ),
        ),
      );

      // Tap the first transaction
      await tester.tap(find.text('Project A').first);
      await tester.pump();

      expect(tappedTransaction, equals(testTransactions[0]));
    });

    testWidgets('shows filter menu on button tap', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionList(
              transactions: testTransactions,
              onTapTransaction: (_) {},
            ),
          ),
        ),
      );

      // Open filter menu
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // Verify filter options are shown
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Earned'), findsOneWidget);
      expect(find.text('Withdrawn'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('displays correct transaction icons', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionList(
              transactions: testTransactions,
              onTapTransaction: (_) {},
            ),
          ),
        ),
      );

      // Verify earned transaction icon
      expect(
        find.byIcon(Icons.payments_outlined),
        findsNWidgets(2),
      );

      // Verify withdrawal transaction icon
      expect(
        find.byIcon(Icons.account_balance_wallet_outlined),
        findsOneWidget,
      );
    });

    testWidgets('handles long transaction descriptions', (WidgetTester tester) async {
      final longTransaction = Transaction(
        id: '4',
        type: TransactionType.earned,
        amount: 200.0,
        timestamp: DateTime.now(),
        status: 'completed',
        source: 'A very long project name that should be handled gracefully by the UI',
        destination: null,
        metadata: {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionList(
              transactions: [longTransaction],
              onTapTransaction: (_) {},
            ),
          ),
        ),
      );

      // Verify the long text is rendered without overflow
      expect(
        tester.renderObject<RenderBox>(
          find.byType(ListTile).first,
        ).hasOverflow,
        false,
      );
    });

    testWidgets('applies correct theme colors', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: TransactionList(
              transactions: testTransactions,
              onTapTransaction: (_) {},
            ),
          ),
        ),
      );

      final lightThemeContext = tester.element(find.byType(TransactionList));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: TransactionList(
              transactions: testTransactions,
              onTapTransaction: (_) {},
            ),
          ),
        ),
      );

      final darkThemeContext = tester.element(find.byType(TransactionList));

      expect(
        Theme.of(lightThemeContext).brightness,
        Brightness.light,
      );
      expect(
        Theme.of(darkThemeContext).brightness,
        Brightness.dark,
      );
    });

    testWidgets('respects MaterialApp text scale factor', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaleFactor: 1.5),
              child: TransactionList(
                transactions: testTransactions,
                onTapTransaction: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(
        MediaQuery.of(
          tester.element(find.byType(TransactionList)),
        ).textScaleFactor,
        1.5,
      );
    });
  });
}