import 'dart:async';
import 'dart:convert';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import './data_models.dart';
import './exceptions.dart';

class DeviceDiscovery {
  bool isDiscovering = false;
  bool discoveryStarted = false;
  StreamSubscription<BluetoothDiscoveryResult>? _streamSubscription;
  List<BluetoothDiscoveryResult> results =
      List<BluetoothDiscoveryResult>.empty(growable: true);

  DeviceDiscovery();

  List<BluetoothDevice> get devices => List<BluetoothDevice>.generate(
      results.length, (index) => results[index].device);

  void restart() {
    stop();
    results.clear();
    start();
  }

  void start() {
    _streamSubscription =
        FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
      final existingIndex = results.indexWhere(
          (element) => element.device.address == result.device.address);
      if (existingIndex >= 0)
        results[existingIndex] = result;
      else
        results.add(result);
    });
    discoveryStarted = true;
    _streamSubscription!.onDone(() => isDiscovering = false);
  }

  void stop() {
    _streamSubscription?.cancel();
    isDiscovering = false;
    discoveryStarted = false;
  }
}

class SetupManager {
  final String esp32Addr;
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  StreamSubscription<BluetoothState>? _btStateStream;
  StreamSubscription<dynamic>? _espDataStream;
  BluetoothConnection? _espCnxn;
  bool _paired = false;

  SetupManager(this.esp32Addr);

  Future<void> initialise() async {
    _bluetooth.state.then((state) => _bluetoothState = state);
    if ((await FlutterBluetoothSerial.instance.isEnabled) ?? false)
      throw BluetoothDisabledException();
    _btStateStream = _bluetooth.onStateChanged().listen((BluetoothState state) {
      _bluetoothState = state;
      if (_bluetoothState != BluetoothState.STATE_ON)
        throw BluetoothDisabledException();
    });
    _btStateStream!.onError((error) => throw error);
  }

  Future<void> pairESP32() async {
    _paired = (await _bluetooth.bondDeviceAtAddress(esp32Addr))!;
    if (!_paired) throw BluetoothConnectionError('Could not pair ESP32');
  }

  Future<void> connect() async {
    if (!_paired) throw BluetoothConnectionError('ESP32 is not paired');
    await BluetoothConnection.toAddress(esp32Addr)
        .then((cnxn) => _espCnxn = cnxn);
  }

  Future<void> transferCredentials(SetupCredential credential) async {
    try {
      _espCnxn!.output.add(ascii.encode(credential.payload));
      await _espCnxn!.output.allSent;
      _espDataStream = _espCnxn!.input!.listen((data) async {
        String setupResult = ascii.decode(data);
        if (!setupResult.contains('done')) throw SetupException('Setup failed');
        await _espDataStream!.cancel();
      });
      _espDataStream!.onError((error) async {
        await _espDataStream!.cancel();
        throw error;
      });
    } on StateError {
      throw BluetoothConnectionError(
          'Setup failed, please check bluetooth connection');
    } on SetupException {
      rethrow;
    } on Exception catch (e) {
      throw SetupException(e.toString());
    }
  }

  void cleanup() {
    _btStateStream?.cancel();
    _espDataStream?.cancel();
    _espCnxn?.finish();
  }
}
