import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_theme.dart';
import '../models/spatial_anchor.dart';
import '../services/blockchain_service.dart';
import '../services/monetization_service.dart';

class AnchorDetailsSheet extends ConsumerWidget {
  final SpatialAnchor anchor;

  const AnchorDetailsSheet({
    Key? key,
    required this.anchor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final monetizationService = ref.watch(monetizationProvider);
    final blockchainService = ref.watch(blockchainProvider);

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(theme),
          SizedBox(height: 16),
          _buildDetails(theme),
          SizedBox(height: 16),
          _buildEarningsSection(theme, monetizationService),
          SizedBox(height: 16),
          _buildBlockchainInfo(theme, blockchainService),
          SizedBox(height: 24),
          _buildActions(context, theme),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.location_on,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spatial Anchor',
                style: theme.textTheme.titleLarge,
              ),
              Text(
                anchor.id,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetails(ThemeData theme) {
    return Card(
      elevation: AppTheme.elevationLow,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Details',
              style: theme.textTheme.titleMedium,
            ),
            SizedBox(height: 8),
            _buildDetailRow(
              theme,
              'Created',
              anchor.createdAt.toString(),
            ),
            _buildDetailRow(
              theme,
              'Position',
              '(${anchor.x.toStringAsFixed(2)}, ${anchor.y.toStringAsFixed(2)}, ${anchor.z.toStringAsFixed(2)})',
            ),
            _buildDetailRow(
              theme,
              'Status',
              anchor.isActive ? 'Active' : 'Inactive',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsSection(
    ThemeData theme,
    MonetizationService monetizationService,
  ) {
    return Card(
      elevation: AppTheme.elevationLow,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppTheme.earningsGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Earnings',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            StreamBuilder<double>(
              stream: monetizationService.getAnchorEarnings(anchor.id),
              builder: (context, snapshot) {
                final earnings = snapshot.data ?? 0.0;
                return Text(
                  '\$${earnings.toStringAsFixed(2)}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockchainInfo(
    ThemeData theme,
    BlockchainService blockchainService,
  ) {
    return Card(
      elevation: AppTheme.elevationLow,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Blockchain Info',
              style: theme.textTheme.titleMedium,
            ),
            SizedBox(height: 8),
            FutureBuilder<Map<String, dynamic>>(
              future: blockchainService.getAnchorTransactions(anchor.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data ?? {};
                return Column(
                  children: [
                    _buildDetailRow(
                      theme,
                      'Total Transactions',
                      data['totalTransactions']?.toString() ?? '0',
                    ),
                    _buildDetailRow(
                      theme,
                      'Last Transaction',
                      data['lastTransaction']?.toString() ?? 'N/A',
                    ),
                    _buildDetailRow(
                      theme,
                      'Contract Address',
                      data['contractAddress']?.toString() ?? 'N/A',
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
        SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () {
            // TODO: Implement anchor editing
          },
          icon: Icon(Icons.edit),
          label: Text('Edit'),
        ),
      ],
    );
  }
}