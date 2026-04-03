// example/lib/models/ei_models.dart
//
// Real-world Firestore models demonstrating all supported features:
// - Inheritance
// - Custom converters (DateTime, GeoPoint)
// - @JsonKey defaults and custom names
// - Nullable fields
// - Enums
// - Nested models
// - Lists with converters

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:dart_ts_generator/src/annotations.dart';

part 'ei_models.g.dart';

// ─────────────────────────────────────────────────────────────
// CONVERTERS
// ─────────────────────────────────────────────────────────────

class DateTimeConverter implements JsonConverter<DateTime, Object> {
  const DateTimeConverter();

  @override
  DateTime fromJson(Object json) {
    if (json is Timestamp) return json.toDate();
    if (json is int) return DateTime.fromMillisecondsSinceEpoch(json);
    return DateTime.parse(json.toString());
  }

  @override
  Object toJson(DateTime date) => Timestamp.fromDate(date);
}

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
  List<DateTime> fromJson(List<dynamic> json) =>
      json.map((e) => const DateTimeConverter().fromJson(e)).toList();

  @override
  List<dynamic> toJson(List<DateTime> dates) =>
      dates.map((d) => Timestamp.fromDate(d)).toList();
}

GeoPoint? _fromJsonGeoPoint(Map<String, dynamic>? json) {
  if (json == null) return null;
  return GeoPoint(json['lat'] as double, json['lng'] as double);
}

Map<String, dynamic>? _toJsonGeoPoint(GeoPoint? geoPoint) {
  if (geoPoint == null) return null;
  return {'lat': geoPoint.latitude, 'lng': geoPoint.longitude};
}

// ─────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────

enum EiAppSource { admin, user, other }

enum EiUserRole { rider, admin, superAdmin, guest }

enum EiRideStatus { pending, active, completed, cancelled }

// ─────────────────────────────────────────────────────────────
// BASE MODEL
// ─────────────────────────────────────────────────────────────

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

  factory EiModel.fromJson(Map<String, dynamic> json) =>
      _$EiModelFromJson(json);

  Map<String, dynamic> toJson() => _$EiModelToJson(this);
}

// ─────────────────────────────────────────────────────────────
// ADDRESS (nested model)
// ─────────────────────────────────────────────────────────────

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

  factory EiAddress.fromJson(Map<String, dynamic> json) =>
      _$EiAddressFromJson(json);

  Map<String, dynamic> toJson() => _$EiAddressToJson(this);
}

// ─────────────────────────────────────────────────────────────
// USER (extends EiModel)
// ─────────────────────────────────────────────────────────────

@JsonSerializable()
class EiUser extends EiModel {
  @JsonKey(name: 'user_id')
  String? userId;

  String? name;
  String? email;
  String? phone;

  @JsonKey(name: 'profile_photo_url')
  String? profilePhotoUrl;

  @JsonKey(defaultValue: EiUserRole.rider)
  EiUserRole role;

  @JsonKey(defaultValue: false)
  bool isVerified;

  @JsonKey(defaultValue: 0.0)
  double rating;

  @JsonKey(defaultValue: 0)
  int totalRides;

  @JsonKey(name: 'rider_categories', defaultValue: [])
  List<String> riderCategories;

  @JsonKey(name: 'kms_driven', defaultValue: 0.0)
  double kmsDriven;

  EiAddress? address;

  @JsonKey(fromJson: _fromJsonGeoPoint, toJson: _toJsonGeoPoint)
  GeoPoint? geoPoint;

  @JsonKey(name: 'device_tokens', defaultValue: [])
  List<String> deviceTokens;

  @JsonKey(name: 'blocked_user_ids', defaultValue: [])
  List<String> blockedUserIds;

  @TsIgnore()
  String? internalCache;

  EiUser({
    this.userId,
    this.name,
    this.email,
    this.phone,
    this.profilePhotoUrl,
    this.role = EiUserRole.rider,
    this.isVerified = false,
    this.rating = 0.0,
    this.totalRides = 0,
    this.riderCategories = const [],
    this.kmsDriven = 0.0,
    this.address,
    this.geoPoint,
    this.deviceTokens = const [],
    this.blockedUserIds = const [],
    this.internalCache,
    super.createdAt,
    super.updatedAt,
    super.addedOn,
    super.lastModifiedAppSource,
  });

  factory EiUser.fromJson(Map<String, dynamic> json) => _$EiUserFromJson(json);

  Map<String, dynamic> toJson() => _$EiUserToJson(this);
}

// ─────────────────────────────────────────────────────────────
// RIDE (extends EiModel, uses DateTime list converter)
// ─────────────────────────────────────────────────────────────

@JsonSerializable()
class EiRide extends EiModel {
  @JsonKey(name: 'ride_id')
  String? rideId;

  @JsonKey(name: 'rider_id')
  String? riderId;

  @JsonKey(name: 'driver_id')
  String? driverId;

  @JsonKey(defaultValue: EiRideStatus.pending)
  EiRideStatus status;

  EiAddress? pickupAddress;
  EiAddress? dropAddress;

  @JsonKey(name: 'fare_amount', defaultValue: 0.0)
  double fareAmount;

  @JsonKey(name: 'distance_km', defaultValue: 0.0)
  double distanceKm;

  @DateTimeNullableConverter()
  @JsonKey(name: 'started_at')
  DateTime? startedAt;

  @DateTimeNullableConverter()
  @JsonKey(name: 'ended_at')
  DateTime? endedAt;

  @DateTimeListConverter()
  @JsonKey(name: 'checkpoint_times', defaultValue: [])
  List<DateTime> checkpointTimes;

  EiRide({
    this.rideId,
    this.riderId,
    this.driverId,
    this.status = EiRideStatus.pending,
    this.pickupAddress,
    this.dropAddress,
    this.fareAmount = 0.0,
    this.distanceKm = 0.0,
    this.startedAt,
    this.endedAt,
    this.checkpointTimes = const [],
    super.createdAt,
    super.updatedAt,
    super.addedOn,
    super.lastModifiedAppSource,
  });

  factory EiRide.fromJson(Map<String, dynamic> json) => _$EiRideFromJson(json);

  Map<String, dynamic> toJson() => _$EiRideToJson(this);
}
