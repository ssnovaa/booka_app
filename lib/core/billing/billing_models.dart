import 'package:flutter/foundation.dart';

enum BillingStatus { idle, loadingProducts, ready, error }

enum BillingPurchaseState { none, purchasing, purchased, restoring, error }

class BillingProduct {
  BillingProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  });

  final String id;
  final String title;
  final String description;
  final String price;
}

class BillingError {
  BillingError({required this.message, this.raw});

  final String message;
  final Object? raw;

  @override
  String toString() => describeIdentity(this);
}
