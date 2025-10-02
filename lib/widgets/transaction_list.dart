import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/user_earnings.dart';
import 'package:intl/intl.dart';

class TransactionList extends StatelessWidget {
  final List<Transaction> transactions;
  final Function(Transaction) onTapTransaction;
  final String? filterType;

  const TransactionList({
    Key? key,
    required this.transactions,
    required this.onTapTransaction,
    this.filterType,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredTransactions = _getFilteredTransactions();

    return Card(
      elevation: AppTheme.elevationLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Transaction History',
                  style: theme.textTheme.titleMedium,
                ),
                _buildFilterButton(context),
              ],
            ),
          ),
          if (filteredTransactions.isEmpty)
            _buildEmptyState(theme)
          else
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.symmetric(horizontal: 8),
                itemCount: filteredTransactions.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                ),
                itemBuilder: (context, index) {
                  return _buildTransactionItem(
                    filteredTransactions[index],
                    theme,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterButton(BuildContext context) {
    final theme = Theme.of(context);
    
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.filter_list,
        color: theme.colorScheme.primary,
      ),
      tooltip: 'Filter transactions',
      itemBuilder: (BuildContext context) => [
        PopupMenuItem<String>(
          value: null,
          child: Text('All'),
        ),
        PopupMenuItem<String>(
          value: 'earned',
          child: Text('Earned'),
        ),
        PopupMenuItem<String>(
          value: 'withdrawn',
          child: Text('Withdrawn'),
        ),
        PopupMenuItem<String>(
          value: 'pending',
          child: Text('Pending'),
        ),
      ],
      onSelected: (String? value) {
        // Handle filter selection
        // This will be handled by the parent widget through state management
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            SizedBox(height: 16),
            Text(
              'No transactions found',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (filterType != null) ...[
              SizedBox(height: 8),
              Text(
                'Try changing the filter',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionItem(Transaction transaction, ThemeData theme) {
    final dateFormat = DateFormat('MMM d, yyyy h:mm a');
    final amount = NumberFormat.currency(symbol: '\$').format(transaction.amount);
    
    return ListTile(
      onTap: () => onTapTransaction(transaction),
      leading: CircleAvatar(
        backgroundColor: _getTransactionColor(transaction.status, theme),
        child: Icon(
          _getTransactionIcon(transaction.type),
          color: theme.colorScheme.surface,
          size: 20,
        ),
      ),
      title: Text(
        _getTransactionTitle(transaction),
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: Text(
        dateFormat.format(transaction.timestamp),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            amount,
            style: theme.textTheme.titleMedium?.copyWith(
              color: _getAmountColor(transaction, theme),
            ),
          ),
          Text(
            transaction.status.toUpperCase(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: _getTransactionColor(transaction.status, theme),
            ),
          ),
        ],
      ),
    );
  }

  List<Transaction> _getFilteredTransactions() {
    if (filterType == null) return transactions;
    
    return transactions.where((transaction) {
      switch (filterType) {
        case 'earned':
          return transaction.type == TransactionType.earned;
        case 'withdrawn':
          return transaction.type == TransactionType.withdrawal &&
                 transaction.status == 'completed';
        case 'pending':
          return transaction.status == 'pending';
        default:
          return true;
      }
    }).toList();
  }

  String _getTransactionTitle(Transaction transaction) {
    switch (transaction.type) {
      case TransactionType.earned:
        return 'Earnings from ${transaction.source}';
      case TransactionType.withdrawal:
        return 'Withdrawal to ${transaction.destination}';
      default:
        return 'Unknown Transaction';
    }
  }

  IconData _getTransactionIcon(TransactionType type) {
    switch (type) {
      case TransactionType.earned:
        return Icons.payments_outlined;
      case TransactionType.withdrawal:
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Color _getTransactionColor(String status, ThemeData theme) {
    switch (status.toLowerCase()) {
      case 'completed':
        return theme.colorScheme.primary;
      case 'pending':
        return theme.colorScheme.tertiary;
      case 'failed':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.outline;
    }
  }

  Color _getAmountColor(Transaction transaction, ThemeData theme) {
    if (transaction.type == TransactionType.withdrawal) {
      return theme.colorScheme.error;
    }
    return theme.colorScheme.primary;
  }
}