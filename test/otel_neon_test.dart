// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_neon/otel_neon.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_neon-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('SELECT records CLIENT span with parsed operation', () async {
    await tracedNeonQuery<String>(
      statement: 'SELECT * FROM users WHERE id = \$1',
      database: 'shop',
      branch: 'main',
      collection: 'users',
      invoke: () async => const NeonQueryResult(
        value: 'rows',
        rowCount: 1,
        command: 'SELECT',
      ),
    );
    final span = spans.findSpanByName('SELECT users');
    expect(span, isNotNull);
    expect(span!.kind, SpanKind.client);
    final a = attrsOf(span);
    expect(a['db.system'], 'postgresql');
    expect(a['db.name'], 'shop');
    expect(a['db.operation'], 'SELECT');
    expect(a['db.collection.name'], 'users');
    expect(a['neon.database'], 'shop');
    expect(a['neon.branch'], 'main');
    expect(a['neon.driver'], 'serverless');
    expect(a['db.row_count'], 1);
    expect(a['postgresql.command'], 'SELECT');
  });

  test('WITH ... is treated as known op', () async {
    await tracedNeonQuery<String>(
      statement: 'WITH cte AS (SELECT 1) SELECT * FROM cte',
      database: 'shop',
      invoke: () async => const NeonQueryResult(value: 'ok'),
    );
    expect(spans.findSpanByName('WITH'), isNotNull);
  });

  test('records exception', () async {
    await expectLater(
      tracedNeonQuery<String>(
        statement: 'SELECT 1',
        database: 'shop',
        invoke: () async => throw StateError('boom'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(spans.findSpanByName('SELECT')!.status, SpanStatusCode.Error);
  });

  test('suppression skips spans', () async {
    await runWithoutNeonInstrumentationAsync(() async {
      await tracedNeonQuery<String>(
        statement: 'SELECT 1',
        database: 'shop',
        invoke: () async => const NeonQueryResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('SELECT'), isEmpty);
  });
}
