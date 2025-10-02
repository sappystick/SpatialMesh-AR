import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_theme.dart';
import '../models/user_payment_preferences.dart';

class WithdrawDialog extends StatefulWidget {
  final double availableBalance;
  final List<PaymentMethod> savedPaymentMethods;
  final Function(double amount, PaymentMethod method) onConfirm;

  const WithdrawDialog({
    Key? key,
    required this.availableBalance,
    required this.savedPaymentMethods,
    required this.onConfirm,
  }) : super(key: key);

  @override
  State<WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends State<WithdrawDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  PaymentMethod? _selectedMethod;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    if (widget.savedPaymentMethods.isNotEmpty) {
      _selectedMethod = widget.savedPaymentMethods.first;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      elevation: AppTheme.elevationHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Withdraw Earnings',
                  style: theme.textTheme.titleLarge,
                ),
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            SizedBox(height: 24),
            Text(
              'Available Balance: \$${widget.availableBalance.toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(height: 24),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: 'Amount to Withdraw',
                      prefixText: '\$',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    validator: _validateAmount,
                    onChanged: (_) => setState(() {}),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Select Payment Method',
                    style: theme.textTheme.titleSmall,
                  ),
                  SizedBox(height: 8),
                  _buildPaymentMethodSelector(theme),
                  SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canSubmit() ? _handleSubmit : null,
                      child: _isProcessing
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : Text('Withdraw'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSelector(ThemeData theme) {
    if (widget.savedPaymentMethods.isEmpty) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.onErrorContainer,
              ),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'No payment methods available. Please add a payment method in settings.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: widget.savedPaymentMethods.map((method) {
        final isSelected = _selectedMethod == method;
        
        return Card(
          elevation: isSelected ? AppTheme.elevationLow : 0,
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          child: InkWell(
            onTap: () => setState(() => _selectedMethod = method),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Radio<PaymentMethod>(
                    value: method,
                    groupValue: _selectedMethod,
                    onChanged: (value) => setState(() => _selectedMethod = value),
                  ),
                  SizedBox(width: 8),
                  Icon(_getPaymentMethodIcon(method.type)),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          method.name,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: isSelected
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          _formatPaymentDetails(method),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isSelected
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String? _validateAmount(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter an amount';
    }

    final amount = double.tryParse(value);
    if (amount == null) {
      return 'Please enter a valid amount';
    }

    if (amount <= 0) {
      return 'Amount must be greater than zero';
    }

    if (amount > widget.availableBalance) {
      return 'Amount exceeds available balance';
    }

    return null;
  }

  bool _canSubmit() {
    if (_isProcessing) return false;
    if (_selectedMethod == null) return false;
    if (_amountController.text.isEmpty) return false;

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0 || amount > widget.availableBalance) {
      return false;
    }

    return true;
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMethod == null) return;

    setState(() => _isProcessing = true);

    try {
      await widget.onConfirm(
        double.parse(_amountController.text),
        _selectedMethod!,
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to process withdrawal: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  IconData _getPaymentMethodIcon(String type) {
    switch (type.toLowerCase()) {
      case 'bank':
        return Icons.account_balance_outlined;
      case 'paypal':
        return Icons.payment_outlined;
      case 'crypto':
        return Icons.currency_bitcoin_outlined;
      default:
        return Icons.payment_outlined;
    }
  }

  String _formatPaymentDetails(PaymentMethod method) {
    switch (method.type.toLowerCase()) {
      case 'bank':
        return '****${method.details['accountNumber'].substring(method.details['accountNumber'].length - 4)}';
      case 'paypal':
        return method.details['email'];
      case 'crypto':
        final address = method.details['address'];
        return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
      default:
        return '';
    }
  }
}