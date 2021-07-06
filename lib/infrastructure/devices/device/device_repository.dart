import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cybear_jinni/domain/devices/device/device_entity.dart';
import 'package:cybear_jinni/domain/devices/device/devices_failures.dart';
import 'package:cybear_jinni/domain/devices/device/i_device_repository.dart';
import 'package:cybear_jinni/domain/devices/device/value_objects.dart';
import 'package:cybear_jinni/domain/user/i_user_repository.dart';
import 'package:cybear_jinni/domain/user/user_entity.dart';
import 'package:cybear_jinni/infrastructure/core/firestore_helpers.dart';
import 'package:cybear_jinni/infrastructure/core/gen/cbj_hub_server/hub_client.dart';
import 'package:cybear_jinni/infrastructure/core/gen/cbj_hub_server/protoc_as_dart/cbj_hub_server.pbgrpc.dart';
import 'package:cybear_jinni/infrastructure/devices/device/device_dtos.dart';
import 'package:cybear_jinni/infrastructure/devices/device_helper.dart';
import 'package:cybear_jinni/infrastructure/objects/enums.dart';
import 'package:cybear_jinni/injection.dart';
import 'package:dartz/dartz.dart';
import 'package:device_info/device_info.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:kt_dart/kt.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

@LazySingleton(as: IDeviceRepository)
class DeviceRepository implements IDeviceRepository {
  DeviceRepository(this._firestore);

  final FirebaseFirestore _firestore;

  // final DeviceRemoteService _deviceRemoteService;
  // final DeviceLocalService _deviceLocalService;
  HashMap<String, DeviceEntity> allDevices = HashMap<String, DeviceEntity>();

  @override
  void addOrUpdateDevice(DeviceEntity deviceEntity) {
    allDevices[deviceEntity.id!.getOrCrash()!] = deviceEntity;
    devicesStreamController.sink.add(allDevices.values.toImmutableList());
  }

  @override
  void addOrUpdateDeviceAndStateToWaiting(DeviceEntity deviceEntity) {
    addOrUpdateDevice(deviceEntity.copyWith(
        deviceStateGRPC: DeviceState(
            EnumHelper.deviceStateToString(DeviceStateGRPC.waitingInComp))));
  }

  @override
  Future<void> initiateHubConnection() async {
    await HubClient.createStreamWithHub('192.168.31.154');
  }

  @override
  Future<Either<DevicesFailure, KtList<DeviceEntity?>>> getAllDevices() async {
    final homeDoc = await _firestore.currentHomeDocument();

    try {
      final QuerySnapshot allDevicesSnapshot =
          await homeDoc.devicesCollecttion.get();
      return right<DevicesFailure, KtList<DeviceEntity?>>(
          allDevicesSnapshot.docs
              .map((e) {
                if ((e.data()! as Map<String, dynamic>)[
                            GrpcClientTypes.deviceTypesTypeString] ==
                        DeviceTypes.light.toString() ||
                    (e.data()! as Map<String, dynamic>)[
                            GrpcClientTypes.deviceTypesTypeString] ==
                        DeviceTypes.blinds.toString() ||
                    (e.data()! as Map<String, dynamic>)[
                            GrpcClientTypes.deviceTypesTypeString] ==
                        DeviceTypes.boiler.toString()) {
                  return DeviceDtos.fromFirestore(e).toDomain();
                } else {
                  print('Type not supported');
                }
              })
              .where((element) => element != null)
              .toImmutableList());
    } catch (e) {
      if (e is PlatformException && e.message!.contains('PERMISSION_DENIED')) {
        print('Insufficient permission while getting all devices');
        return left(const DevicesFailure.insufficientPermission());
      } else {
        print('Unexpected error while getting all devices');
        // log.error(e.toString());
        return left(const DevicesFailure.unexpected());
      }
    }
  }

  @override
  Stream<Either<DevicesFailure, KtList<DeviceEntity?>>> watchAll() async* {
    yield* devicesStreamController.stream.map((event) => right(event));

    // homeDoc.devicesCollecttion.snapshots().map(
    //       (snapshot) => right<DevicesFailure, KtList<DeviceEntity?>>(
    //         snapshot.docs
    //             .map((doc) {
    //               if ((doc.data()! as Map<String, dynamic>)[
    //                           GrpcClientTypes.deviceTypesTypeString] ==
    //                       DeviceTypes.light.toString() ||
    //                   (doc.data()! as Map<String, dynamic>)[
    //                           GrpcClientTypes.deviceTypesTypeString] ==
    //                       DeviceTypes.blinds.toString() ||
    //                   (doc.data()! as Map<String, dynamic>)[
    //                           GrpcClientTypes.deviceTypesTypeString] ==
    //                       DeviceTypes.boiler.toString()) {
    //                 return DeviceDtos.fromFirestore(doc).toDomain();
    //               } else {
    //                 print('Type not supported');
    //               }
    //             })
    //             .where((element) => element != null)
    //             .toImmutableList(),
    //       ),
    //     );
    //     .onErrorReturnWith((e) {
    //   if (e is PlatformException && e.message!.contains('PERMISSION_DENIED')) {
    //     return left<DevicesFailure, KtList<DeviceEntity>>( DevicesFailure.insufficientPermission());
    //   } else {
    //     // log.error(e.toString());
    //     // return left( DevicesFailure.unexpected());
    //   }
    // });
  }

  @override
  Stream<Either<DevicesFailure, KtList<DeviceEntity?>>> watchLights() async* {
    // Using watchAll devices from server function and filtering out only the
    // Light device type

    yield* watchAll().map((event) => event.fold((l) => left(l), (r) {
          return right(r.toList().asList().where((element) {
            return element!.deviceTypes!.getOrCrash() ==
                DeviceTypes.light.toString();
          }).toImmutableList());
        }));
  }

  @override
  Stream<Either<DevicesFailure, KtList<DeviceEntity?>>> watchBlinds() async* {
    // Using watchAll devices from server function and filtering out only the
    // Blinds device type
    yield* watchAll().map((event) => event.fold((l) => left(l), (r) {
          return right(r.toList().asList().where((element) {
            return element!.deviceTypes!.getOrCrash() ==
                DeviceTypes.blinds.toString();
          }).toImmutableList());
        }));
  }

  @override
  Stream<Either<DevicesFailure, KtList<DeviceEntity?>>> watchBoilers() async* {
    // Using watchAll devices from server function and filtering out only the
    // Boilers device type
    yield* watchAll().map((event) => event.fold((l) => left(l), (r) {
          return right(r.toList().asList().where((element) {
            return element!.deviceTypes!.getOrCrash() ==
                DeviceTypes.boiler.toString();
          }).toImmutableList());
        }));
  }

  @override
  Stream<Either<DevicesFailure, KtList<DeviceEntity>>> watchUncompleted() {
    // TODO: implement watchUncompleted
    throw UnimplementedError();
  }

  @override
  Future<Either<DevicesFailure, Unit>> create(DeviceEntity deviceEntity) async {
    try {
      String deviceModelString = 'No Model found';
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        print(androidInfo.model);
        deviceModelString = androidInfo.model;
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        print(iosInfo.utsname.machine);
        deviceModelString = iosInfo.model;
      }

      final UserEntity currentUserEntity =
          (await getIt<IUserRepository>().getCurrentUser())
              .getOrElse(() => throw 'Cant get current user');
      final String currentUserId = currentUserEntity.id!.getOrCrash()!;

      final DeviceEntity deviceEntityTemp = deviceEntity.copyWith(
          stateMassage: DeviceStateMassage('Setting up device'),
          senderDeviceOs: DeviceSenderDeviceOs(Platform.operatingSystem),
          senderDeviceModel: DeviceSenderDeviceModel(deviceModelString),
          senderId: DeviceSenderId.fromUniqueString(currentUserId));

      final homeDoc = await _firestore.currentHomeDocument();
      final deviceDtos = DeviceDtos.fromDomain(deviceEntityTemp);

      await homeDoc.devicesCollecttion
          .doc(deviceDtos.id)
          .set(deviceDtos.toJson());
      return right(unit);
    } on PlatformException catch (e) {
      if (e.message!.contains('PERMISSION_DENIED')) {
        return left(const DevicesFailure.insufficientPermission());
      } else {
        // log.error(e.toString());
        return left(const DevicesFailure.unexpected());
      }
    }
  }

  @override
  Future<Either<DevicesFailure, Unit>> updateDatabase(
      {required DocumentReference documentPath,
      required Map<String, dynamic> fieldsToUpdate,
      String? forceUpdateLocation}) async {
    try {
      await documentPath.update(fieldsToUpdate);
      return right(unit);
    } on PlatformException catch (e) {
      if (e.message!.contains('NOT_FOUND')) {
        return left(const DevicesFailure.unableToUpdate());
      } else {
        // log.error(e.toString());
        return left(const DevicesFailure.unexpected());
      }
    }
  }

  @override
  Future<Either<DevicesFailure, Unit>> updateWithDeviceEntity({
    required DeviceEntity deviceEntity,
    String? forceUpdateLocation,
  }) async {
    // Assumes that all devices configured for the same second WiFi
    final String? firstDeviceSecondWifiName =
        deviceEntity.deviceSecondWiFi?.value.getOrElse(() => '');

    final String updateLocation = await whereToUpdateDevicesData(
        forceUpdateLocation, firstDeviceSecondWifiName);

    try {
      if (updateLocation == 'L') {
        return updateComputer(deviceEntity);
      }
      return updateRemoteDB(deviceEntity);
    } on PlatformException catch (e) {
      if (e.message!.contains('NOT_FOUND')) {
        return left(const DevicesFailure.unableToUpdate());
      } else {
        // log.error(e.toString());
        return left(const DevicesFailure.unexpected());
      }
    }
  }

  @override
  Future<Either<DevicesFailure, Unit>> turnOnDevices(
      {List<String>? devicesId, String? forceUpdateLocation}) async {
    final List<DeviceEntity?> deviceEntityListToUpdate =
        await getDeviceEntityListFromId(devicesId!);

    final String waitingState =
        EnumHelper.deviceStateToString(DeviceStateGRPC.waitingInFirebase);

    final String actionLightOn =
        EnumHelper.deviceActionToString(DeviceActions.on);

    try {
      deviceEntityListToUpdate.forEach((element) {
        final DeviceEntity dEntity = element!.copyWith(
            deviceStateGRPC: DeviceState(waitingState),
            deviceActions: DeviceAction(actionLightOn));

        updateWithDeviceEntity(deviceEntity: dEntity);
      });
    } on PlatformException catch (e) {
      if (e.message!.contains('PERMISSION_DENIED')) {
        return left(const DevicesFailure.insufficientPermission());
      } else if (e.message!.contains('NOT_FOUND')) {
        return left(const DevicesFailure.unableToUpdate());
      } else {
        // log.error(e.toString());
        return left(const DevicesFailure.unexpected());
      }
    }
    return right(unit);
  }

  @override
  Future<Either<DevicesFailure, Unit>> turnOffDevices(
      {List<String>? devicesId, String? forceUpdateLocation}) async {
    final List<DeviceEntity?> deviceEntityListToUpdate =
        await getDeviceEntityListFromId(devicesId!);

    final String waitingState =
        EnumHelper.deviceStateToString(DeviceStateGRPC.waitingInFirebase);

    final String actionLightOff =
        EnumHelper.deviceActionToString(DeviceActions.off);

    try {
      deviceEntityListToUpdate.forEach((element) {
        final DeviceEntity dea = element!.copyWith(
            deviceStateGRPC: DeviceState(waitingState),
            deviceActions: DeviceAction(actionLightOff));

        updateWithDeviceEntity(deviceEntity: dea);
      });
    } on PlatformException catch (e) {
      if (e.message!.contains('PERMISSION_DENIED')) {
        return left(const DevicesFailure.insufficientPermission());
      } else if (e.message!.contains('NOT_FOUND')) {
        return left(const DevicesFailure.unableToUpdate());
      } else {
        // log.error(e.toString());
        return left(const DevicesFailure.unexpected());
      }
    }
    return right(unit);
  }

  @override
  Future<Either<DevicesFailure, Unit>> moveUpBlinds(
      {List<String>? devicesId, String? forceUpdateLocation}) async {
    try {
      final DocumentReference homeDoc = await _firestore.currentHomeDocument();
      final CollectionReference devicesCollection = homeDoc.devicesCollecttion;

      devicesId!.forEach((element) {
        final DocumentReference deviceDocumentReference =
            devicesCollection.doc(element);
        updateDatabase(documentPath: deviceDocumentReference, fieldsToUpdate: {
          GrpcClientTypes.deviceActionsTypeString:
              DeviceActions.moveUp.toString(),
          GrpcClientTypes.deviceStateGRPCTypeString:
              DeviceStateGRPC.waitingInFirebase.toString()
        });
      });
    } on PlatformException catch (e) {
      if (e.message!.contains('PERMISSION_DENIED')) {
        return left(const DevicesFailure.insufficientPermission());
      } else if (e.message!.contains('NOT_FOUND')) {
        return left(const DevicesFailure.unableToUpdate());
      } else {
        // log.error(e.toString());
        return left(const DevicesFailure.unexpected());
      }
    }
    return right(unit);
  }

  @override
  Future<Either<DevicesFailure, Unit>> stopBlinds(
      {List<String>? devicesId, String? forceUpdateLocation}) async {
    try {
      final DocumentReference homeDoc = await _firestore.currentHomeDocument();
      final CollectionReference devicesCollection = homeDoc.devicesCollecttion;

      devicesId!.forEach((element) {
        final DocumentReference deviceDocumentReference =
            devicesCollection.doc(element);
        updateDatabase(documentPath: deviceDocumentReference, fieldsToUpdate: {
          GrpcClientTypes.deviceActionsTypeString:
              DeviceActions.stop.toString(),
          GrpcClientTypes.deviceStateGRPCTypeString:
              DeviceStateGRPC.waitingInFirebase.toString()
        });
      });
    } on PlatformException catch (e) {
      if (e.message!.contains('PERMISSION_DENIED')) {
        return left(const DevicesFailure.insufficientPermission());
      } else if (e.message!.contains('NOT_FOUND')) {
        return left(const DevicesFailure.unableToUpdate());
      } else {
        // log.error(e.toString());
        return left(const DevicesFailure.unexpected());
      }
    }
    return right(unit);
  }

  @override
  Future<Either<DevicesFailure, Unit>> moveDownBlinds(
      {List<String>? devicesId, String? forceUpdateLocation}) async {
    try {
      final DocumentReference homeDoc = await _firestore.currentHomeDocument();
      final CollectionReference devicesCollection = homeDoc.devicesCollecttion;

      devicesId!.forEach((element) {
        final DocumentReference deviceDocumentReference =
            devicesCollection.doc(element);
        updateDatabase(documentPath: deviceDocumentReference, fieldsToUpdate: {
          GrpcClientTypes.deviceActionsTypeString:
              DeviceActions.moveDown.toString(),
          GrpcClientTypes.deviceStateGRPCTypeString:
              DeviceStateGRPC.waitingInFirebase.toString()
        });
      });
    } on PlatformException catch (e) {
      if (e.message!.contains('PERMISSION_DENIED')) {
        return left(const DevicesFailure.insufficientPermission());
      } else if (e.message!.contains('NOT_FOUND')) {
        return left(const DevicesFailure.unableToUpdate());
      } else {
        // log.error(e.toString());
        return left(const DevicesFailure.unexpected());
      }
    }
    return right(unit);
  }

  @override
  Future<Either<DevicesFailure, Unit>> delete(DeviceEntity deviceEntity) async {
    try {
      final homeDoc = await _firestore.currentHomeDocument();
      final deviceDtos = DeviceDtos.fromDomain(deviceEntity);

      await homeDoc.devicesCollecttion.doc(deviceDtos.id).delete();
      return right(unit);
    } on PlatformException catch (e) {
      if (e.message!.contains('PERMISSION_DENIED')) {
        return left(const DevicesFailure.insufficientPermission());
      } else if (e.message!.contains('NOT_FOUND')) {
        return left(const DevicesFailure.unableToUpdate());
      } else {
        // log.error(e.toString());
        return left(const DevicesFailure.unexpected());
      }
    }
  }

  Future<Either<DevicesFailure, Unit>> updateRemoteDB(
      DeviceEntity deviceEntity) async {
    try {
      addOrUpdateDeviceAndStateToWaiting(deviceEntity);

      final homeDoc = await _firestore.currentHomeDocument();
      final deviceDtos = DeviceDtos.fromDomain(deviceEntity);

      await homeDoc.devicesCollecttion
          .doc(deviceDtos.id)
          .update(deviceDtos.toJson());
      return right(unit);
    } on PlatformException catch (e) {
      if (e.message!.contains('NOT_FOUND')) {
        return left(const DevicesFailure.unableToUpdate());
      } else {
        // log.error(e.toString());
        return left(const DevicesFailure.unexpected());
      }
    }
  }

  Future<Either<DevicesFailure, Unit>> updateComputer(
      DeviceEntity deviceEntity) async {
    try {
      final String id = deviceEntity.id!.getOrCrash()!;
      String? lastKnownIp;

      addOrUpdateDeviceAndStateToWaiting(deviceEntity);

      try {
        lastKnownIp ??= deviceEntity.lastKnownIp?.getOrCrash();

        lastKnownIp = '192.168.31.154';

        final String waitingState =
            EnumHelper.deviceStateToString(DeviceStateGRPC.waitingInFirebase);

        deviceEntity.copyWith(deviceStateGRPC: DeviceState(waitingState));
        //
        final String deviceDtoAsString =
            DeviceHelper.convertDomainToJsonString(deviceEntity);
        final ClientStatusRequests clientStatusRequests = ClientStatusRequests(
          allRemoteCommands: deviceDtoAsString,
          sendingType: SendingType.deviceType,
        );
        AppRequestsToHub.appRequestsToHubStreamController.sink
            .add(clientStatusRequests);
      } catch (e) {
        print('This is the error $e');

        final String mDnsName = deviceEntity.deviceMdnsName!.getOrCrash();
        lastKnownIp = await getDeviceIpByDeviceAvahiName(mDnsName);

        final DocumentReference homeDoc =
            await _firestore.currentHomeDocument();
        final CollectionReference devicesCollection =
            homeDoc.devicesCollecttion;
        final DocumentReference deviceDocumentReference =
            devicesCollection.doc(deviceEntity.id!.getOrCrash());
        updateDatabase(documentPath: deviceDocumentReference, fieldsToUpdate: {
          'lastKnownIp': lastKnownIp,
        });
      }

      return right(unit);
    } catch (e) {
      print('Probably ip of device was not inserted into the device object');
      return left(const DevicesFailure.unexpected());
    }
  }

  Future<List<DeviceEntity?>> getDeviceEntityListFromId(
      List<String> deviceIdList) async {
    final List<DeviceEntity> deviceEntityList = [];

    deviceIdList.forEach((deviceId) {
      deviceEntityList.add(allDevices[deviceId]!);
    });
    return deviceEntityList;
  }

  /// Search device IP by computer Avahi (mdns) name
  Future<String> getDeviceIpByDeviceAvahiName(String mDnsName) async {
    String deviceIp = '';
    final String fullMdnsName = '$mDnsName.local';

    final MDnsClient client = MDnsClient(rawDatagramSocketFactory:
        (dynamic host, int port,
            {bool? reuseAddress, bool? reusePort, int? ttl}) {
      return RawDatagramSocket.bind(host, port, ttl: ttl!);
    });
    // Start the client with default options.

    await client.start();
    await for (final IPAddressResourceRecord record
        in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(fullMdnsName))) {
      deviceIp = record.address.address;
      print('Found address (${record.address}).');
    }

    // await for (final IPAddressResourceRecord record
    //     in client.lookup<IPAddressResourceRecord>(
    //         ResourceRecordQuery.addressIPv6(fullMdnsName))) {
    //   print('Found address (${record.address}).');
    // }

    client.stop();

    print('Done.');

    return deviceIp;
  }

  /// How to send the data, in the local network or the remote server/cloud
  Future<String> whereToUpdateDevicesData(
      String? forceUpdateLocation, String? deviceSecondWifiName) async {
    String updateLocation;

    if (forceUpdateLocation == null) {
      final status = await Permission.location.status;
      if (status.isDenied) {
        Permission.location.request();
      }

      final String? wifiName = await NetworkInfo().getWifiName();

      if (deviceSecondWifiName != null &&
          deviceSecondWifiName.isNotEmpty &&
          deviceSecondWifiName == wifiName) {
        updateLocation = 'L'; // L for local network
      } else {
        updateLocation = 'R'; // R for remote
      }
    } else {
      updateLocation = forceUpdateLocation;
    }

    return updateLocation;
  }

  /// Stream controller of the app request for the hub
  @override
  BehaviorSubject<KtList<DeviceEntity?>> devicesStreamController =
      BehaviorSubject<KtList<DeviceEntity?>>();
}