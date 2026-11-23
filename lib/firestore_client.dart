import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'firebase_config.dart';

/// A failed Firestore request. [network] means the phone couldn't reach
/// Google at all (offline), which callers treat quietly.
class FirestoreException implements Exception {
  final int? status;
  final String message;
  final bool network;
  FirestoreException(this.message, {this.status, this.network = false});

  bool get notFound => status == 404;
  bool get alreadyExists => status == 409;
  bool get denied => status == 403;

  @override
  String toString() => 'FirestoreException($status): $message';
}

/// Tiny Firestore client over the REST API (no native plugin, no Gradle
/// changes). It understands the handful of value types TaskPet uses.
class FirestoreClient {
  final String _base;
  final Future<String> Function() tokenProvider;

  FirestoreClient({
    required this.tokenProvider,
    String? baseUrl,
  }) : _base = baseUrl ??
            'https://firestore.googleapis.com/v1/projects/'
                '${FirebaseConfig.projectId}/databases/(default)/documents';

  // ------------------------------------------------------------ values

  static Map<String, dynamic> encodeValue(Object? v) {
    if (v == null) return {'nullValue': null};
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': '$v'};
    if (v is double) return {'doubleValue': v};
    if (v is String) return {'stringValue': v};
    if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
    if (v is List) {
      return {
        'arrayValue': {'values': v.map(encodeValue).toList()}
      };
    }
    if (v is Map) {
      return {
        'mapValue': {'fields': encodeFields(v.cast<String, Object?>())}
      };
    }
    throw ArgumentError('Unsupported Firestore value: ${v.runtimeType}');
  }

  static Map<String, dynamic> encodeFields(Map<String, Object?> data) =>
      data.map((k, v) => MapEntry(k, encodeValue(v)));

  static Object? decodeValue(Map<String, dynamic> v) {
    if (v.containsKey('stringValue')) return v['stringValue'];
    if (v.containsKey('integerValue')) {
      return int.tryParse('${v['integerValue']}') ?? 0;
    }
    if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
    if (v.containsKey('booleanValue')) return v['booleanValue'];
    if (v.containsKey('timestampValue')) {
      return DateTime.tryParse('${v['timestampValue']}');
    }
    if (v.containsKey('arrayValue')) {
      final values = (v['arrayValue'] as Map)['values'] as List? ?? [];
      return values.map((e) => decodeValue(e as Map<String, dynamic>)).toList();
    }
    if (v.containsKey('mapValue')) {
      final fields = (v['mapValue'] as Map)['fields'] as Map? ?? {};
      return decodeFields(fields.cast<String, dynamic>());
    }
    return null;
  }

  static Map<String, Object?> decodeFields(Map<String, dynamic> fields) =>
      fields.map((k, v) => MapEntry(k, decodeValue(v as Map<String, dynamic>)));

  // ---------------------------------------------------------- requests

  /// Returns the document's fields, or null if it doesn't exist.
  Future<Map<String, Object?>?> getDoc(String path) async {
    final (status, json) = await _request('GET', '$_base/$path');
    if (status == 404) return null;
    _check(status, json);
    final fields = json['fields'];
    return fields is Map ? decodeFields(fields.cast<String, dynamic>()) : {};
  }

  /// Creates or fully replaces the document at [path].
  Future<void> setDoc(String path, Map<String, Object?> data) async {
    final (status, json) = await _request('PATCH', '$_base/$path',
        body: {'fields': encodeFields(data)});
    _check(status, json);
  }

  /// Creates a document with a chosen id. Throws [FirestoreException]
  /// with `alreadyExists` if that id is taken.
  Future<void> createDoc(
      String collection, String id, Map<String, Object?> data) async {
    final (status, json) = await _request(
        'POST', '$_base/$collection?documentId=${Uri.encodeQueryComponent(id)}',
        body: {'fields': encodeFields(data)});
    _check(status, json);
  }

  /// Changes only the listed fields of an existing document.
  Future<void> patchFields(String path, Map<String, Object?> data) async {
    final mask = data.keys
        .map((k) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(k)}')
        .join('&');
    final (status, json) = await _request('PATCH', '$_base/$path?$mask',
        body: {'fields': encodeFields(data)});
    _check(status, json);
  }

  /// All documents in [collection] whose array [field] contains [value].
  Future<List<({String id, Map<String, Object?> data})>> queryArrayContains(
      String collection, String field, String value) async {
    final (status, json) = await _request('POST', '$_base:runQuery', body: {
      'structuredQuery': {
        'from': [
          {'collectionId': collection}
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': field},
            'op': 'ARRAY_CONTAINS',
            'value': {'stringValue': value},
          }
        },
        'limit': 200,
      }
    });
    _check(status, json);
    final rows = json['_list'];
    final out = <({String id, Map<String, Object?> data})>[];
    if (rows is List) {
      for (final r in rows) {
        if (r is! Map || r['document'] is! Map) continue;
        final doc = r['document'] as Map;
        final id = '${doc['name']}'.split('/').last;
        final fields = doc['fields'];
        out.add((
          id: id,
          data: fields is Map ? decodeFields(fields.cast<String, dynamic>()) : {},
        ));
      }
    }
    return out;
  }

  Future<void> deleteDoc(String path) async {
    final (status, json) = await _request('DELETE', '$_base/$path');
    if (status == 404) return;
    _check(status, json);
  }

  void _check(int status, Map<String, dynamic> json) {
    if (status == 200) return;
    final err = json['error'];
    final msg = err is Map ? err['message'] : null;
    throw FirestoreException('${msg ?? 'HTTP $status'}', status: status);
  }

  Future<(int, Map<String, dynamic>)> _request(String method, String url,
      {Object? body}) async {
    final token = await tokenProvider();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl(method, Uri.parse(url));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        req.add(utf8.encode(jsonEncode(body)));
      }
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join();
      Map<String, dynamic> json = {};
      if (text.isNotEmpty) {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          json = decoded;
        } else if (decoded is List) {
          json = {'_list': decoded}; // runQuery answers with a list
        }
      }
      return (res.statusCode, json);
    } on SocketException {
      throw FirestoreException('NETWORK', network: true);
    } on HandshakeException {
      throw FirestoreException('NETWORK', network: true);
    } on TimeoutException {
      throw FirestoreException('NETWORK', network: true);
    } finally {
      client.close();
    }
  }
}
