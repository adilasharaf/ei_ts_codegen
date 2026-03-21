import 'package:build/build.dart';
import 'package:ei_ts_codegen/src/ts_builder.dart';

/// Phase 1 — per-file: emits a .ts_meta.json sidecar for each .dart file.
Builder tsCodegenBuilder(BuilderOptions options) => TsCodegenBuilder(options);

/// Phase 2 — aggregate: reads all .ts_meta.json files and emits
/// models.ts / enums.ts / utils.ts / index.ts.
Builder tsCodegenPostBuilder(BuilderOptions options) =>
    TsCodegenAggregateBuilder(options);
