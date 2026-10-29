import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_store.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/shell/app_shell.dart';
import 'providers.dart';
import 'theme.dart';

class TeenBrainApp extends ConsumerWidget {
  const TeenBrainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(bootstrapProvider);

    return MaterialApp(
      title: 'TeenBrain',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: switch (bootstrap.value == null
          ? AppThemeMode.system
          : ref.watch(settingsProvider).themeMode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      },
      home: bootstrap.when(
        loading: () => const _Booting(),
        error: (error, stack) => _BootFailure(error: error),
        data: (_) => const _Root(),
      ),
    );
  }
}

/// Decides between onboarding and the app itself.
///
/// The profile row is the only signal: it exists exactly when someone has been
/// through onboarding, so there is no separate flag to get out of sync.
class _Root extends ConsumerStatefulWidget {
  const _Root();

  @override
  ConsumerState<_Root> createState() => _RootState();
}

class _RootState extends ConsumerState<_Root> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyRetention());
  }

  /// Retention is enforced once per launch rather than on a timer.
  Future<void> _applyRetention() async {
    final days = ref.read(settingsProvider).retentionDays;
    if (days <= 0) return;

    final cutoff = DateTime.now().subtract(Duration(days: days));
    final timeline = ref.read(timelineRepositoryProvider);
    final events = await timeline.events(before: cutoff, limit: 5000);
    for (final event in events) {
      await timeline.delete(event.id);
    }
    if (events.isNotEmpty) ref.read(dataRevisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);

    return profile.when(
      loading: () => const _Booting(),
      error: (error, _) => _BootFailure(error: error),
      data: (value) {
        if (value == null || !value.isOnboarded) {
          return OnboardingPage(
            onDone: () => ref.invalidate(profileProvider),
          );
        }
        return const AppShell();
      },
    );
  }
}

class _Booting extends StatelessWidget {
  const _Booting();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('TeenBrain', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 18),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BootFailure extends StatelessWidget {
  const _BootFailure({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TeenBrain kunne ikke starte',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(
                  'Den lokale database kunne ikke åbnes. Fejlen var:',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                SelectableText('$error', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
