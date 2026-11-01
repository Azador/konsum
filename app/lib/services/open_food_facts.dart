import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:konsum_core/konsum_core.dart';

/// Produktdaten von Open Food Facts (https://world.openfoodfacts.org) und
/// seinen Schwester-Datenbanken für Kosmetik, Tierfutter und sonstige
/// Produkte. Mit `product_type=all` leitet Open Food Facts selbst an die
/// passende Datenbank weiter. Die Daten stehen unter der Open Database
/// License (ODbL).
class OpenFoodFacts {
  OpenFoodFacts({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _fields =
      'product_name,product_name_de,brands,quantity,'
      'image_front_small_url,nutriments,nutriscore_grade,product_type';

  /// Name der Datenbank je Produktart, für die Quellenangabe.
  static const databases = {
    'food': 'Open Food Facts',
    'beauty': 'Open Beauty Facts',
    'petfood': 'Open Pet Food Facts',
    'product': 'Open Products Facts',
  };

  /// Quellenangabe für Produktdaten der Art [productType].
  static String sourceOf(String? productType) =>
      '${databases[productType] ?? databases['food']} (ODbL)';

  /// Nährwerte, die übernommen werden (je 100 g/ml).
  static const nutrimentKeys = [
    'energy-kcal',
    'fat',
    'saturated-fat',
    'carbohydrates',
    'sugars',
    'proteins',
    'salt',
  ];

  static bool isProductCode(String code) =>
      RegExp(r'^\d{8,14}$').hasMatch(code);

  /// Sucht ein Produkt. Null, wenn es unbekannt ist; wirft bei Netzfehlern.
  Future<ProductInfo?> lookup(String code) async {
    if (!isProductCode(code)) return null;
    final uri = Uri.https(
      'world.openfoodfacts.org',
      '/api/v2/product/$code.json',
      {'fields': _fields, 'product_type': 'all'},
    );
    final res = await _client
        .get(
          uri,
          // Im Browser darf der User-Agent nicht gesetzt werden.
          headers: kIsWeb
              ? const {}
              : const {'User-Agent': 'Konsum/0.1 (de.azadoro.konsum)'},
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', uri);
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
    final product = json['product'];
    if (json['status'] != 1 || product is! Map) return null;
    String? text(String key) {
      final v = product[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final nutriments = product['nutriments'];
    return ProductInfo(
      name: text('product_name_de') ?? text('product_name'),
      brand: text('brands'),
      quantity: text('quantity'),
      imageUrl: text('image_front_small_url'),
      nutriScore: text('nutriscore_grade'),
      productType: text('product_type'),
      nutriments: {
        if (nutriments is Map)
          for (final k in nutrimentKeys)
            if (nutriments['${k}_100g'] case final num v) k: v,
      },
    );
  }
}

/// Gemeinsame Instanz für die App.
final openFoodFacts = OpenFoodFacts();
