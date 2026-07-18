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

  Future<void> restock({
    required String itemName,
    required String quantity,
    required String unit,
    required String lowStockThreshold,
    String? price,
  }) => _sendJson('/v1/inventory/restock', {
    'item_name': itemName,
    'quantity': quantity,
    'unit': unit,
    'low_stock_threshold': lowStockThreshold,
    if (price != null && price.isNotEmpty) 'last_price_inr': price,
  }, method: 'POST');

  Future<void> updateStock({
    required StockItem item,
    required String quantity,
    required String unit,
    required String lowStockThreshold,
    String? price,
  }) => _sendJson('/v1/inventory/${item.id}', {
    'quantity_on_hand': quantity,
    'unit': unit,
    'low_stock_threshold': lowStockThreshold,
    'last_price_inr': price == null || price.isEmpty ? null : price,
  }, method: 'PUT');

  Future<void> deleteStock(String itemId) =>
      _sendJson('/v1/inventory/$itemId', const {}, method: 'DELETE');

  Future<void> giveCredit({
    required String customerName,
    required String amount,
    required String itemsGiven,
  }) => _sendJson('/v1/credits', {
    'customer_name': customerName,
    'amount': amount,
    'items_given': itemsGiven.isEmpty ? null : itemsGiven,
  }, method: 'POST');

  Future<void> recordPayment({
    required String customerName,
    required String amount,
  }) => _sendJson('/v1/credits/payment', {
    'customer_name': customerName,
    'amount': amount,
  }, method: 'POST');

  Future<void> _sendJson(
    String path,
    Map<String, dynamic> body, {
    required String method,
  }) async {
    final request = http.Request(method, configuration.endpoint(path))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    try {
      final response = await http.Response.fromStream(
        await _client.send(request),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const ShopApiException('The shop record could not be saved.');
      }
    } on ShopApiException {
      rethrow;
    } catch (_) {
      throw const ShopApiException('Could not reach the shop backend.');
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
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.lowStockThreshold,
    required this.price,
    required this.lowStock,
  });

  factory StockItem.fromJson(Map<String, dynamic> json) => StockItem(
    id: json['id'] as String,
    name: json['item_name'] as String,
    quantity: json['quantity_on_hand'].toString(),
    unit: json['unit'] as String,
    lowStockThreshold: json['low_stock_threshold'].toString(),
    price: json['last_price_inr']?.toString() ?? '',
    lowStock:
        (num.tryParse(json['quantity_on_hand'].toString()) ?? 0) <=
        (num.tryParse(json['low_stock_threshold'].toString()) ?? 0),
  );

  final String id;
  final String name;
  final String quantity;
  final String unit;
  final String lowStockThreshold;
  final String price;
  final bool lowStock;
}

class CustomerCredit {
  const CustomerCredit({
    required this.name,
    required this.outstanding,
    required this.itemsGiven,
  });

  factory CustomerCredit.fromJson(Map<String, dynamic> json) => CustomerCredit(
    name: json['customer_name'] as String,
    outstanding: json['outstanding_inr'].toString(),
    itemsGiven: (json['items_given'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList(),
  );

  final String name;
  final String outstanding;
  final List<String> itemsGiven;
}

class ShopApiException implements Exception {
  const ShopApiException(this.message);
  final String message;
}
