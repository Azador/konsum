import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';

import 'oidc_redirect.dart';

/// Eigenes Schema der App. Muss der umgekehrte Host der Client-Adresse sein
/// (`konsum.azadoro.de`), sonst lehnt der Server die Registrierung ab.
const oidcScheme = 'de.azadoro.konsum';

Future<OidcRedirect?> openOidcRedirect() async {
  if (Platform.isAndroid || Platform.isIOS) return _AppLinkRedirect();
  return _LoopbackRedirect.open();
}

/// Android/iOS: Der Browser ruft `de.azadoro.konsum:/oauth` auf, das System
/// gibt die Adresse an die laufende App.
class _AppLinkRedirect implements OidcRedirect {
  final _links = AppLinks();

  @override
  Uri get redirectUri => Uri.parse('$oidcScheme:/oauth');

  @override
  Future<Uri> wait() => _links.uriLinkStream.firstWhere(
    (uri) => uri.scheme == oidcScheme && uri.path == '/oauth',
  );

  @override
  Future<void> close() async {}
}

/// Desktop: Die App wartet auf einem lokalen Port auf den Aufruf aus dem
/// Browser (RFC 8252, Loopback-Umleitung).
class _LoopbackRedirect implements OidcRedirect {
  _LoopbackRedirect(this._server);

  static Future<_LoopbackRedirect> open() async =>
      _LoopbackRedirect(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;

  @override
  Uri get redirectUri => Uri.parse('http://127.0.0.1:${_server.port}/oauth');

  @override
  Future<Uri> wait() async {
    await for (final request in _server) {
      if (request.uri.path != '/oauth') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><meta charset="utf-8"><title>Konsum</title>'
        '<body style="font-family:sans-serif;text-align:center;padding:3em">'
        '<h1>Fertig</h1><p>Du kannst dieses Fenster schließen und zu Konsum '
        'zurückkehren.</p></body>',
      );
      await request.response.close();
      return redirectUri.replace(queryParameters: request.uri.queryParameters);
    }
    throw StateError('Anmeldung abgebrochen');
  }

  @override
  Future<void> close() => _server.close(force: true);
}
