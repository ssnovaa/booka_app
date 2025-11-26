// ПУТЬ: lib/core/billing/billing_models.dart

/// Статус инициализации / завантаження продуктів білінгу.
enum BillingStatus {
  /// Нічого не робимо, ще не ініціалізовані.
  idle,

  /// Іде ініціалізація або запит продуктів у магазину.
  loadingProducts,

  /// Готові до покупок.
  ready,

  /// Сталася помилка.
  error,
}

/// Стан поточної операції покупки / відновлення.
enum BillingPurchaseState {
  /// Немає активної операції.
  none,

  /// Користувач у флоу покупки.
  purchasing,

  /// Покупка успішно завершена.
  purchased,

  /// Іде відновлення покупок.
  restoring,

  /// Сталася помилка.
  error,
}

/// Опис помилки білінгу для UI.
class BillingError {
  /// Людяне повідомлення, яке можна показати користувачу.
  final String message;

  /// Сира помилка / стек / код відповіді — для логів (не обовʼязково).
  final Object? raw;

  /// Робимо конструктор const, щоб можна було писати `const BillingError(...)`.
  const BillingError({
    required this.message,
    this.raw,
  });

  @override
  String toString() => 'BillingError(message: $message, raw: $raw)';
}

/// Спрощена модель продукту для інтерфейсу.
class BillingProduct {
  /// Ідентифікатор продукту в Google Play.
  final String id;

  /// Заголовок, як повертає стор (зазвичай локалізований).
  final String title;

  /// Опис продукту.
  final String description;

  /// Відформатована ціна, наприклад "₴99.00".
  final String price;

  /// Код валюти (UAH, USD тощо). Не завжди потрібен UI, тому опційний.
  final String? currency;

  /// Сирий обʼєкт, який повернув білінг (ProductDetails тощо).
  /// Тип залишаємо Object, щоб не тягнути залежність сюди.
  final Object raw;

  const BillingProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.currency,
    required this.raw,
  });
}
