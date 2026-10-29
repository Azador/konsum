import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:konsum/state/oidc_redirect.dart';

void main() {
  test('Desktop: Rückkehr aus dem Browser über die lokale Adresse', () async {
    final redirect = (await openOidcRedirect())!;
    final uri = redirect.redirectUri;
    expect(uri.scheme, 'http');
    expect(uri.host, '127.0.0.1');
    expect(uri.path, '/oauth');

    final result = redirect.wait();
    final http = HttpClient();
    // Fremde Pfade werden abgewiesen, ohne das Warten zu beenden.
    final other = await (await http.getUrl(uri.replace(path: '/x'))).close();
    expect(other.statusCode, HttpStatus.notFound);
    await other.drain<void>();

    final response = await (await http.getUrl(
      uri.replace(queryParameters: {'code': 'abc', 'state': 'xyz'}),
    )).close();
    expect(await response.transform(utf8.decoder).join(), contains('Fertig'));

    final back = await result;
    expect(back.queryParameters, {'code': 'abc', 'state': 'xyz'});
    http.close();
    await redirect.close();
  });
}
