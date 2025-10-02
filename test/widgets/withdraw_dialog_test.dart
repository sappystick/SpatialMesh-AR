import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/widgets/withdraw_dialog.dart';
import '../../lib/models/user_payment_preferences.dart';

void main() {
  group('WithdrawDialog Widget Tests', () {
    late List<PaymentMethod> testPaymentMethods;
    const double availableBalance = 1000.0;

    setUp(() {
      testPaymentMethods = [
        PaymentMethod(
          id: '1',
          type: 'bank',
          name: 'Main Bank Account',
          details: {'accountNumber': '****1234'},
        ),
        PaymentMethod(
          id: '2',
          type: 'paypal',
          name: 'PayPal Account',
          details: {'email': 'user@example.com'},
        ),
        PaymentMethod(
          id: '3',
          type: 'crypto',
          name: 'Bitcoin Wallet',
          details: {'address': '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa'},
        ),
      ];
    });

    testWidgets('renders dialog with all elements', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => WithdrawDialog(
                      availableBalance: availableBalance,
                      savedPaymentMethods: testPaymentMethods,
                      onConfirm: (_, __) async {},
                    ),
                  );
                },
                child: Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog title and balance
      expect(find.text('Withdraw Earnings'), findsOneWidget);
      expect(
        find.text('Available Balance: \$1,000.00'),
        findsOneWidget,
      );

      // Verify payment methods are rendered
      for (final method in testPaymentMethods) {
        expect(find.text(method.name), findsOneWidget);
      }

      // Verify form elements
      expect(find.text('Amount to Withdraw'), findsOneWidget);
      expect(find.text('Select Payment Method'), findsOneWidget);
      expect(find.text('Withdraw'), findsOneWidget);
    });

    testWidgets('validates withdrawal amount correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WithdrawDialog(
            availableBalance: availableBalance,
            savedPaymentMethods: testPaymentMethods,
            onConfirm: (_, __) async {},
          ),
        ),
      );

      // Try to submit without amount
      await tester.tap(find.text('Withdraw'));
      await tester.pump();
      expect(find.text('Please enter an amount'), findsOneWidget);

      // Enter invalid amount
      await tester.enterText(
        find.byType(TextFormField),
        '2000.00',
      );
      await tester.tap(find.text('Withdraw'));
      await tester.pump();
      expect(find.text('Amount exceeds available balance'), findsOneWidget);

      // Enter valid amount
      await tester.enterText(
        find.byType(TextFormField),
        '500.00',
      );
      await tester.pump();
      expect(find.text('Amount exceeds available balance'), findsNothing);
      expect(find.text('Please enter an amount'), findsNothing);
    });

    testWidgets('handles payment method selection', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WithdrawDialog(
            availableBalance: availableBalance,
            savedPaymentMethods: testPaymentMethods,
            onConfirm: (_, __) async {},
          ),
        ),
      );

      // Verify first method is selected by default
      final firstMethodCard = find.ancestor(
        of: find.text(testPaymentMethods[0].name),
        matching: find.byType(Card),
      );
      expect(
        tester.widget<Card>(firstMethodCard).color,
        Theme.of(tester.element(firstMethodCard)).colorScheme.primaryContainer,
      );

      // Select second method
      await tester.tap(find.text(testPaymentMethods[1].name));
      await tester.pump();

      final secondMethodCard = find.ancestor(
        of: find.text(testPaymentMethods[1].name),
        matching: find.byType(Card),
      );
      expect(
        tester.widget<Card>(secondMethodCard).color,
        Theme.of(tester.element(secondMethodCard)).colorScheme.primaryContainer,
      );
    });

    testWidgets('processes withdrawal correctly', (WidgetTester tester) async {
      double? confirmedAmount;
      PaymentMethod? confirmedMethod;

      await tester.pumpWidget(
        MaterialApp(
          home: WithdrawDialog(
            availableBalance: availableBalance,
            savedPaymentMethods: testPaymentMethods,
            onConfirm: (amount, method) async {
              confirmedAmount = amount;
              confirmedMethod = method;
            },
          ),
        ),
      );

      // Enter amount and submit
      await tester.enterText(find.byType(TextFormField), '500.00');
      await tester.tap(find.text('Withdraw'));
      await tester.pump();

      expect(confirmedAmount, 500.00);
      expect(confirmedMethod, equals(testPaymentMethods[0]));
    });

    testWidgets('shows loading state during processing', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WithdrawDialog(
            availableBalance: availableBalance,
            savedPaymentMethods: testPaymentMethods,
            onConfirm: (_, __) async {
              await Future.delayed(Duration(seconds: 1));
            },
          ),
        ),
      );

      // Enter amount
      await tester.enterText(find.byType(TextFormField), '500.00');
      
      // Tap withdraw and verify loading state
      await tester.tap(find.text('Withdraw'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Withdraw'), findsNothing);
    });

    testWidgets('handles empty payment methods list', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WithdrawDialog(
            availableBalance: availableBalance,
            savedPaymentMethods: [],
            onConfirm: (_, __) async {},
          ),
        ),
      );

      expect(
        find.text('No payment methods available. Please add a payment method in settings.'),
        findsOneWidget,
      );
      expect(
        find.byType(ElevatedButton),
        findsOneWidget,
      );
      expect(
        tester.widget<ElevatedButton>(
          find.byType(ElevatedButton),
        ).enabled,
        false,
      );
    });

    testWidgets('formats payment method details correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WithdrawDialog(
            availableBalance: availableBalance,
            savedPaymentMethods: testPaymentMethods,
            onConfirm: (_, __) async {},
          ),
        ),
      );

      // Verify bank account format
      expect(find.text('****1234'), findsOneWidget);

      // Verify PayPal format
      expect(find.text('user@example.com'), findsOneWidget);

      // Verify crypto address format
      final address = '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa';
      expect(
        find.text('${address.substring(0, 6)}...${address.substring(address.length - 4)}'),
        findsOneWidget,
      );
    });

    testWidgets('handles error state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WithdrawDialog(
              availableBalance: availableBalance,
              savedPaymentMethods: testPaymentMethods,
              onConfirm: (_, __) async {
                throw Exception('Withdrawal failed');
              },
            ),
          ),
        ),
      );

      // Enter amount and submit
      await tester.enterText(find.byType(TextFormField), '500.00');
      await tester.tap(find.text('Withdraw'));
      await tester.pump();

      // Verify error state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      
      await tester.pump();
      expect(find.text('Failed to process withdrawal: Exception: Withdrawal failed'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Withdraw'), findsOneWidget);
    });
  });
}