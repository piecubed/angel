import 'dart:async';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_route/angel_route.dart';
import 'package:mime/mime.dart';

typedef StaticFileCallback(File file, RequestContext req, ResponseContext res);

final RegExp _param = new RegExp(r':([A-Za-z0-9_]+)(\((.+)\))?');
final RegExp _straySlashes = new RegExp(r'(^/+)|(/+$)');

String _pathify(String path) {
  var p = path.replaceAll(_straySlashes, '');

  Map<String, String> replace = {};

  for (Match match in _param.allMatches(p)) {
    if (match[3] != null) replace[match[0]] = ':${match[1]}';
  }

  replace.forEach((k, v) {
    p = p.replaceAll(k, v);
  });

  return p;
}

class VirtualDirectory {
  final bool debug;
  String _prefix;
  Directory _source;
  Directory get source => _source;
  final StaticFileCallback callback;
  final List<String> indexFileNames;
  final String publicPath;

  VirtualDirectory(
      {Directory source,
      this.debug: false,
      this.indexFileNames: const ['index.html'],
      this.publicPath: '/',
      this.callback}) {
    _prefix = publicPath.replaceAll(_straySlashes, '');

    if (source != null) {
      _source = source;
    } else {
      String dirPath = Platform.environment['ANGEL_ENV'] == 'production'
          ? './build/web'
          : './web';
      _source = new Directory(dirPath);
    }
  }

  _printDebug(msg) {
    if (debug) print(msg);
  }

  call(AngelBase app) async => serve(app);

  Future<bool> sendFile(
      File file, RequestContext req, ResponseContext res) async {
    _printDebug('Sending file ${file.absolute.path}...');
    _printDebug('MIME type for ${file.path}: ${lookupMimeType(file.path)}');
    res.statusCode = 200;

    if (callback != null) {
      var r = callback(file, req, res);
      r = r is Future ? await r : r;
      if (r != null && r != true) return r;
    }

    res.headers[HttpHeaders.CONTENT_TYPE] = lookupMimeType(file.path);
    await res.streamFile(file);
    return false;
  }

  void serve(Router router) {
    _printDebug('Source directory: ${source.absolute.path}');
    _printDebug('Public path prefix: "$_prefix"');
    router.get('$publicPath/*',
        (RequestContext req, ResponseContext res) async {
      var path = req.path.replaceAll(_straySlashes, '');
      return serveFile(path, req, res);
    });
  }

  serveFile(String path, RequestContext req, ResponseContext res) async {
    if (_prefix.isNotEmpty) {
      path = path.replaceAll(new RegExp('^' + _pathify(_prefix)), '');
    }

    final file = new File.fromUri(source.absolute.uri.resolve(path));
    _printDebug('Attempting to statically serve file: ${file.absolute.path}');

    if (await file.exists()) {
      return sendFile(file, req, res);
    } else {
      // Try to resolve index
      if (path.isEmpty) {
        for (String indexFileName in indexFileNames) {
          final index =
              new File.fromUri(source.absolute.uri.resolve(indexFileName));
          if (await index.exists()) {
            return await sendFile(index, req, res);
          }
        }
      } else {
        _printDebug('File "$path" does not exist, and is not an index.');
        return true;
      }
    }
  }
}
