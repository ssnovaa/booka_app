// lib/screens/subscriptions_screen.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/models/user.dart' show UserType;
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/widgets/booka_app_bar.dart';
import 'package:booka_app/services/billing_service.dart';

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: bookaAppBar(actions: const []),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'Підписки',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.2),
            ),
            const SizedBox(height: 6),
            Text(
              'Оберіть підписку, щоб відкрити весь каталог і слухати без обмежень.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            const SubscriptionSection(),
          ],
        ),
      ),
    );
  }
}

class SubscriptionSection extends StatelessWidget {
  const SubscriptionSection({super.key});

  @override
  Widget build(BuildContext context) {
    final userNotifier = context.watch<UserNotifier>();
    final billing = context.watch<BillingService>();

    final bool isPaidNow = userNotifier.isPaidNow;
    debugPrint(
      'Billing UI: build, isPaidNow=$isPaidNow, '
          'productLoaded=${billing.product != null}, '
          'querying=${billing.isQuerying}, error=${billing.error}',
    );

    if (isPaidNow) {
      final until = userNotifier.user?.paidUntil;
      final subtitle = until != null
          ? 'Активно до: ${until.toLocal().toString().substring(0, 10)}'
          : 'Преміум активний';

      return _CardWrap(
        title: 'Booka Premium',
        child: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    Widget body;
    if (billing.isQuerying) {
      body = const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Завантаження підписки…'),
        ],
      );
    } else if (billing.error != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            billing.error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () {
                  billing.reloadProduct();
                },
                child: const Text('Оновити'),
              ),
              OutlinedButton(
                onPressed: () {
                  billing.restorePurchases();
                },
                child: const Text('Відновити'),
              ),
            ],
          ),
        ],
      );
    } else if (!billing.hasProduct) {
      body = Row(
        children: [
          const Expanded(
            child: Text('Немає інформації про товар'),
          ),
          OutlinedButton(
            onPressed: () {
              billing.reloadProduct();
            },
            child: const Text('Оновити'),
          ),
        ],
      );
    } else {
      final price = billing.product!.price;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Місячна підписка: $price',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed:
                billing.isBuying ? null : () => billing.buySubscription(),
                child: Text(
                  billing.isBuying ? 'Обробка…' : 'Підключити Premium',
                ),
              ),
              OutlinedButton(
                onPressed: () {
                  billing.restorePurchases();
                },
                child: const Text('Відновити покупку'),
              ),
            ],
          ),
        ],
      );
    }

    return _CardWrap(
      title: 'Booka Premium',
      child: body,
    );
  }
}

class _CardWrap extends StatelessWidget {
  final String title;
  final Widget child;

  const _CardWrap({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: theme.dividerColor.withOpacity(isDark ? 0.25 : 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (isDark)
                Icon(
                  Icons.workspace_premium,
                  color: theme.colorScheme.tertiary,
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
