// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_neon/otel_neon.dart';

/// Traces Neon calls with OpenTelemetry.
///
/// `otel_neon` depends on the OpenTelemetry API only, so the application
/// initializes an SDK once at startup. Wrap each Neon call in
/// [tracedNeonQuery]; the `invoke` callback makes the real call and reports what
/// came back, which is recorded on the span.
Future<void> main() async {
  await OTel.initialize(serviceName: 'neon-example');

  // Wraps a Neon serverless-driver SQL query in a CLIENT span.
  final neonQueryId = await tracedNeonQuery<String>(
    statement: 'active',
    database: 'example',
    branch: 'example',
    collection: 'orders',
    invoke: () async {
      // Make the Neon call here, then report what it returned.
      const id = 'neon_8f3a2c';
      return const NeonQueryResult(value: id, rowCount: 3, command: 'example');
    },
  );
  OTelLog.info('tracedNeonQuery returned $neonQueryId');

  // Calls that should not be traced, such as health checks, run inside
  // runWithoutNeonInstrumentationAsync.
  await runWithoutNeonInstrumentationAsync(
    () => tracedNeonQuery<String>(
      statement: 'active',
      database: 'example',
      branch: 'example',
      collection: 'orders',
      invoke: () async {
        const id = 'neon_8f3a2c';
        return const NeonQueryResult(
            value: id, rowCount: 3, command: 'example');
      },
    ),
  );

  await OTel.shutdown();
}
