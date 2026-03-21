import 'package:build/build.dart';
import 'package:ts_codegen/src/ts_builder.dart';

Builder tsCodegenBuilder(BuilderOptions options) => TsCodegenBuilder(options);

Builder tsCodegenPostBuilder(BuilderOptions options) =>
    TsCodegenAggregateBuilder(options);
