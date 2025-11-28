// lib/screens/subscriptions_screen.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/widgets/booka_app_bar.dart';

// 🔁 Новый биллинг
import 'package:booka_app/core/billing/billing_controller.dart';
import 'package:booka_app/core/billing/billing_models.dart';

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final billing = context.watch<BillingController>();

    // Одноразовая инициализация биллинга, когда экран впервые открылся.
    if (billing.status == BillingStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = context.read<BillingController>();
        if (controller.status == BillingStatus.idle) {
          controller.init();
        }
      });
    }

    return Scaffold(
      appBar: bookaAppBar(actions: const []),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'Підписки',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
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
    final theme = Theme.of(context);

    final userNotifier = context.watch<UserNotifier>();
    final billing = context.watch<BillingController>();

    final bool isPaidNow = userNotifier.isPaidNow || billing.isPaidUser;

    // // УДАЛЕН/ЗАКОММЕНТИРОВАН БЛОК, ВЫЗЫВАВШИЙ СПАМ В КОНСОЛИ
    // debugPrint(
    //   '[SubscriptionsScreen] build: '
    //       'isPaidNow=$isPaidNow, '
    //       'status=${billing.status}, '
    //       'purchaseState=${billing.purchaseState}, '
    //       'hasError=${billing.hasError}, '
    //       'products=${billing.products.length}',
    // );

    // ---- 1. Пользователь уже с активной подпиской ----
    if (isPaidNow) {
      final until = userNotifier.user?.paidUntil;
      final subtitle = until != null
          ? 'Активно до: ${until.toLocal().toString().substring(0, 10)}'
          : 'Преміум активний';

      return _CardWrap(
        title: 'Booka Premium',
        child: Text(
          subtitle,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    // ---- 2. Пользователь без подписки: показываем состояние биллинга ----
    Widget body;

    // 2.1. Загрузка продуктов / покупка / восстановление
    if (billing.isLoading) {
      final bool isRestoring =
          billing.purchaseState == BillingPurchaseState.restoring;

      body = Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            isRestoring ? 'Відновлення покупок…' : 'Завантаження підписки…',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }
    // 2.2. Ошибка инициализации / покупки / восстановления
    else if (billing.hasError && billing.lastError != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            billing.lastError!.message,
            style: TextStyle(
              color: theme.colorScheme.error,
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
                  billing.reloadProducts();
                },
                child: const Text('Оновити'),
              ),
              OutlinedButton(
                onPressed: () {
                  billing.restore();
                },
                child: const Text('Відновити'),
              ),
            ],
          ),
        ],
      );
    }
    // 2.3. Магазин не вернул продукт подписки
    else if (billing.subscriptionProduct == null) {
      body = Row(
        children: [
          const Expanded(
            child: Text('Немає інформації про товар'),
          ),
          OutlinedButton(
            onPressed: () {
              billing.reloadProducts();
            },
            child: const Text('Оновити'),
          ),
        ],
      );
    }
    // 2.4. Нормальное состояние – есть продукт, можно покупать
    else {
      final product = billing.subscriptionProduct!;
      final bool isBuying =
          billing.purchaseState == BillingPurchaseState.purchasing;

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Місячна підписка: ${product.price}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: (billing.isLoading || isBuying)
                    ? null
                    : () {
                  billing.buySubscription();
                },
                child: Text(
                  isBuying ? 'Обробка…' : 'Підключити Premium',
                ),
              ),
              OutlinedButton(
                onPressed: billing.isLoading
                    ? null
                    : () {
                  billing.restore();
                },
                child: Text(
                  billing.purchaseState == BillingPurchaseState.restoring
                      ? 'Відновлення…'
                      : 'Відновити покупку',
                ),
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