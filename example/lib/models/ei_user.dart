// example/lib/models/ei_user.dart
//
// EiUser extends EiModel (defined in ei_base.dart).
// The generator will emit:
//   import { EiModelSchema, EiAddressSchema, EiUserRoleSchema } from './ei_base.g';
// in the generated ei_user.g.ts.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:dart_ts_generator/src/annotations.dart';
import 'ei_base.dart';

part 'ei_user.g.dart';

GeoPoint? _fromJsonGeoPoint(Map<String, dynamic>? json) {
  if (json == null) return null;
  return GeoPoint(json['lat'] as double, json['lng'] as double);
}

Map<String, dynamic>? _toJsonGeoPoint(GeoPoint? geoPoint) {
  if (geoPoint == null) return null;
  return {'lat': geoPoint.latitude, 'lng': geoPoint.longitude};
}

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
    this.internalCache,
    super.createdAt,
    super.updatedAt,
    super.addedOn,
    super.lastModifiedAppSource,
  });

  factory EiUser.fromJson(Map<String, dynamic> json) => _$EiUserFromJson(json);
  Map<String, dynamic> toJson() => _$EiUserToJson(this);
}
