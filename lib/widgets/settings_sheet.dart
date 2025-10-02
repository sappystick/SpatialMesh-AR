import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_theme.dart';
import '../services/analytics_service.dart';
import '../providers/providers.dart';

class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final analytics = ref.watch(analyticsProvider);
    final settings = ref.watch(settingsProvider);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(theme),
          SizedBox(height: 24),
          _buildGeneralSettings(context, theme, ref),
          SizedBox(height: 16),
          _buildPrivacySettings(context, theme, ref),
          SizedBox(height: 16),
          _buildNetworkSettings(context, theme, ref),
          SizedBox(height: 16),
          _buildAboutSection(context, theme),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Text(
          'Settings',
          style: theme.textTheme.headlineSmall,
        ),
        Spacer(),
        IconButton(
          icon: Icon(Icons.close),
          onPressed: () => Navigator.pop(_),
        ),
      ],
    );
  }

  Widget _buildGeneralSettings(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
  ) {
    return Card(
      elevation: AppTheme.elevationLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'General',
              style: theme.textTheme.titleMedium,
            ),
          ),
          ListTile(
            title: Text('Theme'),
            subtitle: Text(ref.watch(themeProvider).isDark ? 'Dark' : 'Light'),
            leading: Icon(Icons.brightness_6),
            onTap: () => _showThemeDialog(context, ref),
          ),
          ListTile(
            title: Text('Language'),
            subtitle: Text(ref.watch(localeProvider).languageCode.toUpperCase()),
            leading: Icon(Icons.language),
            onTap: () => _showLanguageDialog(context, ref),
          ),
          SwitchListTile(
            title: Text('Notifications'),
            subtitle: Text('Receive push notifications'),
            value: ref.watch(settingsProvider).notifications,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).toggleNotifications();
              ref.read(analyticsProvider).trackEvent(
                'settings_changed',
                {'notifications': value},
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacySettings(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
  ) {
    return Card(
      elevation: AppTheme.elevationLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Privacy',
              style: theme.textTheme.titleMedium,
            ),
          ),
          SwitchListTile(
            title: Text('Analytics'),
            subtitle: Text('Help improve the app by sending usage data'),
            value: ref.watch(settingsProvider).analytics,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).toggleAnalytics();
              ref.read(analyticsProvider).trackEvent(
                'settings_changed',
                {'analytics': value},
              );
            },
          ),
          SwitchListTile(
            title: Text('Location Services'),
            subtitle: Text('Use precise location for AR features'),
            value: ref.watch(settingsProvider).locationServices,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).toggleLocationServices();
              ref.read(analyticsProvider).trackEvent(
                'settings_changed',
                {'location_services': value},
              );
            },
          ),
          ListTile(
            title: Text('Data & Privacy'),
            subtitle: Text('Manage your data and privacy settings'),
            leading: Icon(Icons.security),
            onTap: () async {
              final url = Uri.parse('https://spatialmesh.app/privacy');
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkSettings(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
  ) {
    return Card(
      elevation: AppTheme.elevationLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Network',
              style: theme.textTheme.titleMedium,
            ),
          ),
          SwitchListTile(
            title: Text('Auto-Connect'),
            subtitle: Text('Automatically connect to mesh network'),
            value: ref.watch(settingsProvider).autoConnect,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).toggleAutoConnect();
              ref.read(analyticsProvider).trackEvent(
                'settings_changed',
                {'auto_connect': value},
              );
            },
          ),
          ListTile(
            title: Text('Network Status'),
            subtitle: Text(
              ref.watch(meshStateProvider).isConnected
                  ? 'Connected'
                  : 'Disconnected',
            ),
            leading: Icon(Icons.network_check),
          ),
          ListTile(
            title: Text('Blockchain Network'),
            subtitle: Text(ref.watch(blockchainProvider).networkName),
            leading: Icon(Icons.link),
            onTap: () => _showNetworkDialog(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context, ThemeData theme) {
    return Card(
      elevation: AppTheme.elevationLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'About',
              style: theme.textTheme.titleMedium,
            ),
          ),
          ListTile(
            title: Text('Version'),
            subtitle: Text('1.0.0 (build 123)'),
            leading: Icon(Icons.info_outline),
          ),
          ListTile(
            title: Text('Terms of Service'),
            leading: Icon(Icons.description),
            onTap: () async {
              final url = Uri.parse('https://spatialmesh.app/terms');
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
            },
          ),
          ListTile(
            title: Text('Support'),
            leading: Icon(Icons.help_outline),
            onTap: () async {
              final url = Uri.parse('https://spatialmesh.app/support');
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Choose Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Light'),
              leading: Icon(Icons.brightness_5),
              onTap: () {
                ref.read(themeProvider.notifier).setTheme(false);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text('Dark'),
              leading: Icon(Icons.brightness_3),
              onTap: () {
                ref.read(themeProvider.notifier).setTheme(true);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text('System'),
              leading: Icon(Icons.brightness_auto),
              onTap: () {
                ref.read(themeProvider.notifier).setSystemTheme();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Choose Language'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('English'),
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(Locale('en'));
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text('Spanish'),
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(Locale('es'));
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text('French'),
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(Locale('fr'));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showNetworkDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Choose Network'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Ethereum Mainnet'),
              subtitle: Text('Production network'),
              onTap: () {
                ref.read(blockchainProvider).switchNetwork('mainnet');
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text('Polygon'),
              subtitle: Text('Layer 2 scaling solution'),
              onTap: () {
                ref.read(blockchainProvider).switchNetwork('polygon');
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text('Testnet'),
              subtitle: Text('Development network'),
              onTap: () {
                ref.read(blockchainProvider).switchNetwork('testnet');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}