// example/lib/models/ei_ride.dart

import 'package:json_annotation/json_annotation.dart';
import 'ei_base.dart';

part 'ei_ride.g.dart';

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
