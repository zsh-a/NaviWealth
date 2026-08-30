import 'package:naviwealth/core/async/isolate_runner.dart';

import 'ingest_pipeline.dart';

typedef IngestPlanningExecutor = Future<IngestPlanningAnalysis> Function(
  IngestPlanningRequest request,
);

/// Native runs in a background isolate; Web uses the shared yielding fallback.
Future<IngestPlanningAnalysis> runIngestPlanning(
  IngestPlanningRequest request,
) => runInIsolate(() => analyzeIngestPlanning(request));
