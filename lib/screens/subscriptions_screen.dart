// lib/screens/subscriptions_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/core/billing/billing_controller.dart';
import 'package:booka_app/core/billing/billing_models.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/widgets/booka_app_bar.dart';

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
    final billing = context.watch<BillingController>();
    final userNotifier = context.watch<UserNotifier>();
    final theme = Theme.of(context);

    if (userNotifier.isPaidNow) {
      final until = userNotifier.user?.paidUntil;
      final subtitle = until != null
          ? 'Активно до: ${until.toLocal().toString().substring(0, 10)}'
          : 'Преміум активний';
      return _CardWrap(
        title: 'Booka Premium',
        child: Text(subtitle, style: theme.textTheme.bodyMedium),
      );
    }

    final isProcessing = billing.purchaseState == BillingPurchaseState.purchasing ||
        billing.purchaseState == BillingPurchaseState.restoring;
    final canBuy = billing.status == BillingStatus.ready && billing.product != null;

    Widget content;
    if (billing.status == BillingStatus.loadingProducts) {
      content = const Row(
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
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            billing.error!.message,
            style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: billing.reloadProducts,
                child: const Text('Оновити'),
              ),
              OutlinedButton(
                onPressed: billing.restore,
                child: const Text('Відновити'),
              ),
            ],
          ),
        ],
      );
    } else if (billing.product == null) {
      content = Row(
        children: [
          const Expanded(child: Text('Немає інформації про товар')),
          OutlinedButton(
            onPressed: billing.reloadProducts,
            child: const Text('Оновити'),
          ),
        ],
      );
    } else {
      final product = billing.product!;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Місячна підписка: ${product.price}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(product.description, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: canBuy && !isProcessing ? billing.buyPremium : null,
                icon: isProcessing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.workspace_premium_outlined),
                label: Text(isProcessing ? 'Обробка…' : 'Підключити Premium'),
              ),
              OutlinedButton(
                onPressed: isProcessing ? null : billing.restore,
                child: const Text('Відновити покупку'),
              ),
            ],
          ),
          if (billing.purchaseState == BillingPurchaseState.error &&
              billing.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                billing.error!.message,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
              ),
            ),
        ],
      );
    }

    return _CardWrap(title: 'Booka Premium', child: content);
  }
}

class _CardWrap extends StatelessWidget {
  const _CardWrap({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.3)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
