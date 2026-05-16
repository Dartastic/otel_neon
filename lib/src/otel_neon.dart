// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_neon_suppression.dart';

const _tracerName = 'dartastic_otel_libs_neon';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Pair returned from `tracedNeonQuery` callback.
class NeonQueryResult<T> {
  const NeonQueryResult({required this.value, this.rowCount, this.command});
  final T value;
  final int? rowCount;

  /// Postgres `command` tag — typically the verb (SELECT/INSERT/...)
  final String? command;
}

const _maxStatementLength = 1024;
String _truncate(String s) =>
    s.length <= _maxStatementLength ? s : s.substring(0, _maxStatementLength);

/// Wraps a Neon serverless-driver SQL query in a CLIENT span.
/// db.system is `postgresql` (Neon speaks Postgres wire protocol).
Future<T> tracedNeonQuery<T>({
  required String statement,
  required String database,
  required Future<NeonQueryResult<T>> Function() invoke,
  String? branch,
  String? operation,
  String? collection,
}) async {
  if (neonInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final op = operation ?? _operationFromStatement(statement);
  final m = <String, Object>{
    'db.system': 'postgresql',
    'db.name': database,
    'db.statement': _truncate(statement),
    'neon.database': database,
    'neon.driver': 'serverless',
    if (op != null) 'db.operation': op,
    if (collection != null) 'db.collection.name': collection,
  };
  if (branch != null) m['neon.branch'] = branch;

  final spanName =
      collection == null ? (op ?? 'query') : '${op ?? 'query'} $collection';
  final span = _tracer().startSpan(
    spanName,
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    final extras = <Attribute<Object>>[];
    if (r.rowCount != null) {
      extras.add(OTel.attributeInt('db.row_count', r.rowCount!));
    }
    if (r.command != null) {
      extras.add(OTel.attributeString('postgresql.command', r.command!));
    }
    if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

String? _operationFromStatement(String statement) {
  final trimmed = statement.trimLeft();
  if (trimmed.isEmpty) return null;
  final first = trimmed.split(RegExp(r'\s+')).first.toUpperCase();
  const known = {
    'SELECT',
    'INSERT',
    'UPDATE',
    'DELETE',
    'BEGIN',
    'COMMIT',
    'ROLLBACK',
    'CREATE',
    'ALTER',
    'DROP',
    'TRUNCATE',
    'WITH',
  };
  return known.contains(first) ? first : null;
}
