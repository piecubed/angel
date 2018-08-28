import 'package:angel_framework/angel_framework.dart';
import 'package:angel_static/angel_static.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:http/http.dart' show Client;
import 'package:logging/logging.dart';
import 'package:matcher/matcher.dart';
import 'package:test/test.dart';

main() {
  Angel app;
  AngelHttp http;
  Directory testDir = const LocalFileSystem().directory('test');
  String url;
  Client client = new Client();

  setUp(() async {
    app = new Angel();
    http = new AngelHttp(app);

    app.fallback(
      new CachingVirtualDirectory(app, const LocalFileSystem(),
          source: testDir, maxAge: 350, onlyInProduction: false,
          //publicPath: '/virtual',
          indexFileNames: ['index.txt']).handleRequest,
    );

    app.get('*', (req, res) => 'Fallback');

    app.dumpTree(showMatchers: true);

    app.logger = new Logger('angel_static')
      ..onRecord.listen((rec) {
        print(rec);
        if (rec.error != null) print(rec.error);
        if (rec.stackTrace != null) print(rec.stackTrace);
      });

    var server = await http.startServer();
    url = "http://${server.address.host}:${server.port}";
  });

  tearDown(() async {
    if (http.httpServer != null) await http.httpServer.close(force: true);
  });

  test('sets etag, cache-control, expires, last-modified', () async {
    var response = await client.get("$url");

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');
    print('Response headers: ${response.headers}');

    expect(response.statusCode, equals(200));
    expect(
        ['etag', 'cache-control', 'expires', 'last-modified'],
        everyElement(predicate(
            response.headers.containsKey, 'contained in response headers')));
  });

  test('if-modified-since', () async {
    var response = await client.get("$url", headers: {
      'if-modified-since':
          formatDateForHttp(new DateTime.now().add(new Duration(days: 365)))
    });

    print('Response status: ${response.statusCode}');

    expect(response.statusCode, equals(304));
    expect(
        ['cache-control', 'expires', 'last-modified'],
        everyElement(predicate(
            response.headers.containsKey, 'contained in response headers')));
  });
}
