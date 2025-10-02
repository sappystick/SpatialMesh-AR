import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../services/monetization_service.dart';
import '../services/analytics_service.dart';
import '../services/security_service.dart';
import '../models/user_earnings.dart';
import '../widgets/earnings_chart.dart';
import '../widgets/transaction_list.dart';
import '../widgets/withdraw_dialog.dart';

class EarningsDashboard extends ConsumerStatefulWidget {
  const EarningsDashboard({Key? key}) : super(key: key);

  @override
  ConsumerState<EarningsDashboard> createState() => _EarningsDashboardState();
}

class _EarningsDashboardState extends ConsumerState<EarningsDashboard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final AnalyticsService _analytics;
  late final SecurityService _security;
  DateTime _selectedPeriod = DateTime.now();
  String _selectedTimeRange = 'week';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _analytics = ref.read(analyticsProvider);
    _security = ref.read(securityProvider);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    try {
      // Authenticate user for sensitive data
      final authenticated = await _security.authenticateUser();
      if (!authenticated) {
        Navigator.of(context).pop();
        return;
      }

      _analytics.trackEvent('earnings_dashboard_loaded', {
        'time_range': _selectedTimeRange,
        'selected_period': _selectedPeriod.toString(),
      });
    } catch (e) {
      _analytics.trackEvent('earnings_dashboard_error', {'error': e.toString()});
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;

    return Scaffold(
      appBar: AppBar(
        title: Text('Earnings Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'Analytics'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SafeArea(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(theme, isLandscape),
                  _buildAnalyticsTab(theme, isLandscape),
                  _buildHistoryTab(theme),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showWithdrawDialog(),
        icon: Icon(Icons.account_balance_wallet),
        label: Text('Withdraw'),
      ),
    );
  }

  Widget _buildOverviewTab(ThemeData theme, bool isLandscape) {
    return Consumer(
      builder: (context, ref, _) {
        final earnings = ref.watch(earningsProvider);

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: AppTheme.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEarningsHeader(theme, earnings),
                    SizedBox(height: 24),
                    _buildQuickStats(theme, earnings),
                    SizedBox(height: 24),
                    _buildTimeRangeSelector(theme),
                    SizedBox(height: 16),
                    Container(
                      height: 300,
                      child: EarningsChart(
                        data: earnings.historicalData,
                        timeRange: _selectedTimeRange,
                        onSelectDate: (date) {
                          setState(() => _selectedPeriod = date);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: AppTheme.screenPadding,
                child: Text(
                  'Recent Activity',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            SliverPadding(
              padding: AppTheme.screenPadding,
              sliver: TransactionList(
                transactions: earnings.recentTransactions,
                maxItems: 5,
                showViewAll: true,
                onViewAll: () => _tabController.animateTo(2),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEarningsHeader(ThemeData theme, UserEarnings earnings) {
    final currencyFormat = NumberFormat.currency(symbol: '\$');

    return Card(
      elevation: AppTheme.elevationMedium,
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: AppTheme.earningsGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total Earnings',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              currencyFormat.format(earnings.totalEarnings),
              style: theme.textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildEarningsDetail(
                  theme,
                  'Available',
                  currencyFormat.format(earnings.availableBalance),
                ),
                _buildEarningsDetail(
                  theme,
                  'Pending',
                  currencyFormat.format(earnings.pendingBalance),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEarningsDetail(
    ThemeData theme,
    String label,
    String value,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white70,
          ),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats(ThemeData theme, UserEarnings earnings) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            theme,
            'Active Anchors',
            earnings.activeAnchors.toString(),
            Icons.location_on,
            theme.colorScheme.primary,
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            theme,
            'Today\'s Earnings',
            '\$${earnings.todayEarnings.toStringAsFixed(2)}',
            Icons.trending_up,
            theme.colorScheme.tertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: AppTheme.elevationLow,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRangeSelector(ThemeData theme) {
    return SegmentedButton<String>(
      segments: [
        ButtonSegment(
          value: 'day',
          label: Text('Day'),
          icon: Icon(Icons.calendar_today),
        ),
        ButtonSegment(
          value: 'week',
          label: Text('Week'),
          icon: Icon(Icons.calendar_view_week),
        ),
        ButtonSegment(
          value: 'month',
          label: Text('Month'),
          icon: Icon(Icons.calendar_view_month),
        ),
        ButtonSegment(
          value: 'year',
          label: Text('Year'),
          icon: Icon(Icons.calendar_today),
        ),
      ],
      selected: {_selectedTimeRange},
      onSelectionChanged: (Set<String> selection) {
        setState(() => _selectedTimeRange = selection.first);
        _analytics.trackEvent('earnings_time_range_changed', {
          'range': selection.first,
        });
      },
    );
  }

  Widget _buildAnalyticsTab(ThemeData theme, bool isLandscape) {
    return Consumer(
      builder: (context, ref, _) {
        final earnings = ref.watch(earningsProvider);

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: AppTheme.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Earnings Analytics',
                      style: theme.textTheme.headlineSmall,
                    ),
                    SizedBox(height: 24),
                    _buildAnalyticsCharts(theme, earnings),
                    SizedBox(height: 24),
                    _buildPerformanceMetrics(theme, earnings),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnalyticsCharts(ThemeData theme, UserEarnings earnings) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Card(
            elevation: AppTheme.elevationLow,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Earnings by Anchor',
                    style: theme.textTheme.titleMedium,
                  ),
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sections: earnings.anchorEarnings.map((entry) {
                          return PieChartSectionData(
                            value: entry.amount,
                            title: '${entry.anchorId}\n\$${entry.amount}',
                            radius: 100,
                            color: AppTheme.chartColorPalette[
                              earnings.anchorEarnings.indexOf(entry) %
                                  AppTheme.chartColorPalette.length
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Card(
            elevation: AppTheme.elevationLow,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hourly Distribution',
                    style: theme.textTheme.titleMedium,
                  ),
                  Expanded(
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        barGroups: earnings.hourlyEarnings.map((entry) {
                          return BarChartGroupData(
                            x: entry.hour,
                            barRods: [
                              BarChartRodData(
                                toY: entry.amount,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceMetrics(ThemeData theme, UserEarnings earnings) {
    return Card(
      elevation: AppTheme.elevationLow,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Metrics',
              style: theme.textTheme.titleMedium,
            ),
            SizedBox(height: 16),
            _buildMetricRow(
              theme,
              'Average Daily Earnings',
              '\$${earnings.averageDailyEarnings.toStringAsFixed(2)}',
            ),
            _buildMetricRow(
              theme,
              'Best Performing Anchor',
              earnings.bestPerformingAnchor ?? 'N/A',
            ),
            _buildMetricRow(
              theme,
              'Total Active Time',
              _formatDuration(earnings.totalActiveTime),
            ),
            _buildMetricRow(
              theme,
              'Earnings per Hour',
              '\$${earnings.earningsPerHour.toStringAsFixed(2)}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
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
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(ThemeData theme) {
    return Consumer(
      builder: (context, ref, _) {
        final earnings = ref.watch(earningsProvider);

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: AppTheme.screenPadding,
              sliver: TransactionList(
                transactions: earnings.allTransactions,
                maxItems: null,
                showViewAll: false,
              ),
            ),
          ],
        );
      },
    );
  }

  void _showWithdrawDialog() {
    showDialog(
      context: context,
      builder: (context) => WithdrawDialog(),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '$hours hrs ${minutes}min';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}