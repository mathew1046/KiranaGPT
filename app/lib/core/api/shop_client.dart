import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kirana_gpt/core/api/api_configuration.dart';

class ShopApiClient {
  ShopApiClient({required this.configuration, http.Client? client})
    : _client = client ?? http.Client();

  final ApiConfiguration configuration;
  final http.Client _client;

  Future<ShopSnapshot> loadSnapshot() async {
    final responses = await Future.wait([
      _client.get(configuration.endpoint('/v1/inventory')),
      _client.get(configuration.endpoint('/v1/credits')),
    ]);
    if (responses.any(
      (response) => response.statusCode < 200 || response.statusCode >= 300,
    )) {
      throw const ShopApiException('Could not load stock and credit details.');
    }
    try {
      final inventory = jsonDecode(responses[0].body) as Map<String, dynamic>;
      final credits = jsonDecode(responses[1].body) as List<dynamic>;
      return ShopSnapshot(
        stock: (inventory['items'] as List<dynamic>)
            .map((value) => StockItem.fromJson(value as Map<String, dynamic>))
            .toList(),
        credits: credits
            .map(
              (value) => CustomerCredit.fromJson(value as Map<String, dynamic>),
            )
            .toList(),
      );
    } on FormatException {
      throw const ShopApiException('The shop data could not be read.');
    } on TypeError {
      throw const ShopApiException('The shop data could not be read.');
    }
  }
}

class ShopSnapshot {
  const ShopSnapshot({required this.stock, required this.credits});

  final List<StockItem> stock;
  final List<CustomerCredit> credits;
}

class StockItem {
  const StockItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.lowStock,
  });

  factory StockItem.fromJson(Map<String, dynamic> json) => StockItem(
    name: json['item_name'] as String,
    quantity: json['quantity_on_hand'].toString(),
    unit: json['unit'] as String,
    lowStock:
        json['quantity_on_hand'].toString() ==
            json['low_stock_threshold'].toString() ||
        num.tryParse(json['quantity_on_hand'].toString())! <=
            num.tryParse(json['low_stock_threshold'].toString())!,
  );

  final String name;
  final String quantity;
  final String unit;
  final bool lowStock;
}

class CustomerCredit {
  const CustomerCredit({required this.name, required this.outstanding});

  factory CustomerCredit.fromJson(Map<String, dynamic> json) => CustomerCredit(
    name: json['customer_name'] as String,
    outstanding: json['outstanding_inr'].toString(),
  );

  final String name;
  final String outstanding;
}

class ShopApiException implements Exception {
  const ShopApiException(this.message);
  final String message;
}
