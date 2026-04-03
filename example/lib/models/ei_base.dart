// example/lib/models/ei_base.dart
//
// Base model and enums — other models extend these cross-file.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:dart_ts_generator/src/annotations.dart';

part 'ei_base.g.dart';

// ─── Converters ───────────────────────────────────────────────

class DateTimeNullableConverter implements JsonConverter<DateTime?, Object?> {
  const DateTimeNullableConverter();

  @override
  DateTime? fromJson(Object? json) {
    if (json == null) return null;
    if (json is Timestamp) return json.toDate();
    if (json is int) return DateTime.fromMillisecondsSinceEpoch(json);
    return DateTime.tryParse(json.toString());
  }

  @override
  Object? toJson(DateTime? date) =>
      date != null ? Timestamp.fromDate(date) : null;
}

class DateTimeListConverter
    implements JsonConverter<List<DateTime>, List<dynamic>> {
  const DateTimeListConverter();

  @override
  List<DateTime> fromJson(List<dynamic> json) => json
      .map((e) => const DateTimeNullableConverter().fromJson(e) ?? DateTime.now())
      .toList();

  @override
  List<dynamic> toJson(List<DateTime> dates) =>
      dates.map((d) => Timestamp.fromDate(d)).toList();
}

// ─── Enums ────────────────────────────────────────────────────

enum EiAppSource { admin, user, other }

enum EiUserRole { rider, admin, superAdmin, guest }

enum EiRideStatus { pending, active, completed, cancelled }

// ─── Base Model ───────────────────────────────────────────────

@JsonSerializable()
class EiModel {
  @JsonKey(name: 'created_at')
  @DateTimeNullableConverter()
  DateTime? createdAt;

  @JsonKey(name: 'updated_at')
  @DateTimeNullableConverter()
  DateTime? updatedAt;

  @JsonKey(name: 'added_on')
  @DateTimeNullableConverter()
  DateTime? addedOn;

  @JsonKey(defaultValue: EiAppSource.other)
  EiAppSource lastModifiedAppSource;

  EiModel({
    this.createdAt,
    this.updatedAt,
    this.addedOn,
    this.lastModifiedAppSource = EiAppSource.other,
  });

  factory EiModel.fromJson(Map<String, dynamic> json) => _$EiModelFromJson(json);
  Map<String, dynamic> toJson() => _$EiModelToJson(this);
}

// ─── Address (nested model) ───────────────────────────────────

@JsonSerializable()
class EiAddress {
  String? street;
  String? city;
  String? state;
  String? country;

  @JsonKey(name: 'postal_code')
  String? postalCode;

  double? latitude;
  double? longitude;

  EiAddress({
    this.street,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    this.latitude,
    this.longitude,
  });

  factory EiAddress.fromJson(Map<String, dynamic> json) => _$EiAddressFromJson(json);
  Map<String, dynamic> toJson() => _$EiAddressToJson(this);
}
