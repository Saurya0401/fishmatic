import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import './backend/data_models.dart';
import './backend/exceptions.dart';
import './backend/fishmatic.dart' show Fishmatic, SetupArgs;

class SetupPage extends StatefulWidget {
  const SetupPage({Key? key, required this.setupArgs}) : super(key: key);

  static const route = RouteNames.setup;
  final SetupArgs setupArgs;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  SetupArgs? _setupArgs;
  Fishmatic? _fishmatic;
  TextEditingController? _wifiSsidCtrl, _wifiPassCtrl;
  TextEditingController? _userEmailCtrl, _userPassCtrl;
  String? _statusText;
  BluetoothDevice? _sensor, _actuator;
  BluetoothConnection? _sensorCnxn, _actuatorCnxn;
  Stream<BluetoothDiscoveryResult>? _deviceDiscovery;
  List<BluetoothDiscoveryResult> _discoveryResults =
      List<BluetoothDiscoveryResult>.empty(growable: true);
  bool _isDiscovering = false;
  bool _retrySetup = false;
  bool _settingUp = false;
  bool _validSSID = true;
  bool _validEmail = true;
  bool _validPass = true;
  bool _setupSuccess = false;

  List<BluetoothDevice> get devices => List<BluetoothDevice>.generate(
      _discoveryResults.length, (index) => _discoveryResults[index].device);

  Future<void> _setup() async {
    setState(() {
      _statusText = null;
      _settingUp = true;
      _validSSID = true;
      _validEmail = true;
      _validPass = true;
      if (_wifiSsidCtrl!.text.isEmpty ||
          _userEmailCtrl!.text.isEmpty ||
          _userPassCtrl!.text.isEmpty) {
        _settingUp = false;
        if (_wifiSsidCtrl!.text.isEmpty) _validSSID = false;
        if (_userEmailCtrl!.text.isEmpty) _validEmail = false;
        if (_userPassCtrl!.text.isEmpty) _validPass = false;
      } else {
        _statusText = 'Setting up, please wait...';
      }
    });
    if (_validSSID && _validEmail && _validPass) {
      try {
        if (!(await FlutterBluetoothSerial.instance.isEnabled)!) {
          await _cancelDiscovery();
          throw BluetoothDisabledException();
        }
        if (_retrySetup) await _restartDiscovery();
        if (_setupArgs!.sensorSetup) {
          await _pairESP32(_sensor, DeviceNames.sensor);
          _sensorCnxn = await _connectESP32(_sensor!, DeviceNames.sensor);
          await _transferCredentials(
            SetupCredential(
              _userEmailCtrl!.text,
              _userPassCtrl!.text,
              _wifiSsidCtrl!.text,
              _wifiPassCtrl!.text,
            ),
            _sensorCnxn!,
            DeviceNames.sensor,
          );
          await _waitForSetup(_sensorCnxn!, DeviceNames.sensor);
        }
        if (_setupArgs!.actuatorSetup) {
          await _pairESP32(_actuator, DeviceNames.actuator);
          _actuatorCnxn = await _connectESP32(_actuator!, DeviceNames.actuator);
          await _transferCredentials(
            SetupCredential(
              _userEmailCtrl!.text,
              _userPassCtrl!.text,
              _wifiSsidCtrl!.text,
              _wifiPassCtrl!.text,
            ),
            _actuatorCnxn!,
            DeviceNames.actuator,
          );
          await _waitForSetup(_actuatorCnxn!, DeviceNames.actuator);
        }
        setState(() {
          _settingUp = false;
          _setupSuccess = true;
          _statusText = 'Setup successful!';
        });
      } on BluetoothDisabledException catch (error) {
        _showError('Bluetooth Error', error.message);
      } on BluetoothConnectionError catch (error) {
        _showError('Connection Error', error.message);
      } on SetupException catch (error) {
        _showError('Setup Error', error.message);
      } catch (error) {
        _showError('Error', error.toString());
      } finally {
        await _cancelDiscovery();
      }
    }
  }

  Future<bool> _checkPaired(BluetoothDevice esp32) async {
    List<BluetoothDevice> pairedDevices =
        await FlutterBluetoothSerial.instance.getBondedDevices();
    for (BluetoothDevice device in pairedDevices) {
      if (device.address == esp32.address && device.isBonded) return true;
    }
    return false;
  }

  Future<void> _pairESP32(BluetoothDevice? esp32, String deviceName) async {
    try {
      int secondsElapsed = 0;
      setState(() => _statusText = 'Locating $deviceName ...');
      await Future.doWhile(() async {
        print(secondsElapsed);
        if (secondsElapsed > 120) return false;
        await Future.delayed(Duration(seconds: 5));
        secondsElapsed += 5;
        devices.forEach((device) {
          print(device.address);
          if (device.name == 'UEP15') {
            _sensor = device;
            print('found sensor');
          }
        });
        if (deviceName == DeviceNames.sensor)
          return _sensor == null;
        else
          return _actuator == null;
      }).timeout(
        Timeouts.discovery,
        onTimeout: () => throw SetupException('$deviceName not found'),
      );
      bool sensorPaired = await _checkPaired(esp32!)
          ? true
          : (await FlutterBluetoothSerial.instance
              .bondDeviceAtAddress(esp32.address, pin: '1234'))!;
      if (sensorPaired)
        setState(() => _statusText = 'Paired to $deviceName');
      else
        throw SetupException('Could not pair to $deviceName');
    } on SetupException {
      rethrow;
    } catch (e) {
      throw SetupException(e.toString());
    }
  }

  Future<BluetoothConnection> _connectESP32(
    BluetoothDevice esp32,
    String deviceName,
  ) async {
    BluetoothConnection cnxn =
        await BluetoothConnection.toAddress(esp32.address).catchError((error) {
      throw BluetoothConnectionError(error.toString());
    }).timeout(Timeouts.cnxn,
            onTimeout: () => throw BluetoothConnectionError(
                '$deviceName connection timed out'));
    setState(() => _statusText = 'Connected to $deviceName');
    await Future.delayed(Duration(seconds: 2));
    return cnxn;
  }

  Future<void> _transferCredentials(
    SetupCredential credential,
    BluetoothConnection espCnxn,
    String deviceName,
  ) async {
    try {
      espCnxn.output.add(Uint8List.fromList(utf8.encode(credential.payload)));
      await espCnxn.output.allSent;
      setState(
          () => _statusText = 'Setup credentials transferred to $deviceName');
    } on StateError {
      throw BluetoothConnectionError(
          'Failed to transfer credentials to $deviceName');
    } on SetupException {
      rethrow;
    } catch (e) {
      throw SetupException(e.toString());
    }
  }

  Future<void> _waitForSetup(
    BluetoothConnection espCnxn,
    String deviceName,
  ) async {
    bool noConnectionFlag;
    bool setupModeFlag;
    setState(() => _statusText = 'Waiting for setup to complete...');
    int secondsElapsed = 0;
    await Future.doWhile(() async {
      await Future.delayed(Duration(seconds: 5));
      secondsElapsed += 5;
      print(secondsElapsed);
      if (secondsElapsed > 120) return false;
      if (deviceName == DeviceNames.sensor) {
        noConnectionFlag = await _fishmatic!.noCnxnSensor.flag;
        setupModeFlag = await _fishmatic!.setupSensor.flag;
      } else {
        noConnectionFlag = await _fishmatic!.noCnxnActuator.flag;
        setupModeFlag = await _fishmatic!.setupActuator.flag;
      }
      bool setupOngoing = noConnectionFlag || setupModeFlag;
      if (!setupOngoing) _endCnxn(espCnxn);
      return setupOngoing;
    }).timeout(
      Timeouts.setupWait,
      onTimeout: () {
        _endCnxn(espCnxn);
        throw SetupException('$deviceName setup timed out');
      },
    );
  }

  Future<void> _restartDiscovery() async {
    await _cancelDiscovery();
    setState(() {
      _endCnxn(_sensorCnxn);
      _endCnxn(_actuatorCnxn);
      _discoveryResults.clear();
      _statusText = 'Restarting discovery';
      _sensor = null;
      _actuator = null;
      _startDiscovery();
    });
  }

  Future<void> _cancelDiscovery() async {
    if (_isDiscovering) {
      await FlutterBluetoothSerial.instance.cancelDiscovery();
      _isDiscovering = false;
    }
  }

  void _startDiscovery() {
    if (!_isDiscovering) {
      _deviceDiscovery = FlutterBluetoothSerial.instance.startDiscovery();
      _isDiscovering = true;
    }
  }

  void _endCnxn(BluetoothConnection? _espCnxn) {
    _espCnxn?.dispose();
    _espCnxn = null;
  }

  void _showError(String errorType, String errorMessage) {
    setState(() {
      _settingUp = false;
      _setupSuccess = false;
      _retrySetup = true;
      _statusText = '$errorType\n' + errorMessage;
    });
  }

  @override
  void initState() {
    _setupArgs = widget.setupArgs;
    _fishmatic = _setupArgs!.fishmatic;
    _userEmailCtrl = TextEditingController();
    _userPassCtrl = TextEditingController();
    _wifiSsidCtrl = TextEditingController();
    _wifiPassCtrl = TextEditingController(text: '');
    _startDiscovery();
    super.initState();
  }

  @override
  void dispose() {
    Future.delayed(Duration.zero, () async => await _cancelDiscovery());
    FlutterBluetoothSerial.instance.setPairingRequestHandler(null);
    _endCnxn(_sensorCnxn);
    _endCnxn(_actuatorCnxn);
    _userEmailCtrl?.dispose();
    _userPassCtrl?.dispose();
    _wifiSsidCtrl?.dispose();
    _wifiPassCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BluetoothDiscoveryResult>(
        stream: _deviceDiscovery,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            var r = snapshot.data!;
            final existingIndex = _discoveryResults.indexWhere(
                (element) => element.device.address == r.device.address);
            if (existingIndex >= 0)
              _discoveryResults[existingIndex] = r;
            else
              _discoveryResults.add(r);
            devices.forEach(
              (device) {
                if (device.name == 'UEP15') {
                  _sensor = device;
                }
              },
            );
          }
          return Scaffold(
            appBar: AppBar(
              title: Text(
                'Fishmatic',
                style: TextStyle(
                  fontSize: 25.0,
                  fontStyle: FontStyle.italic,
                ),
              ),
              centerTitle: true,
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 32.0, horizontal: 16.0),
                          child: Text(
                            'Welcome to Fishmatic Setup!',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 250.0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(top: 5.0),
                              child: Text(
                                'Email',
                                style: TextStyle(fontSize: 16.0),
                              ),
                            ),
                            TextField(
                              enabled: !_settingUp,
                              controller: _userEmailCtrl!,
                              decoration: InputDecoration(
                                  isDense: true,
                                  errorText: _validEmail
                                      ? null
                                      : 'Please enter email'),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 20.0),
                              child: Text(
                                'Password',
                                style: TextStyle(fontSize: 16.0),
                              ),
                            ),
                            TextField(
                              enabled: !_settingUp,
                              controller: _userPassCtrl!,
                              obscureText: true,
                              decoration: InputDecoration(
                                  isDense: true,
                                  errorText: _validPass
                                      ? null
                                      : 'Please enter password'),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 20.0),
                              child: Text(
                                'Wifi SSID',
                                style: TextStyle(fontSize: 16.0),
                              ),
                            ),
                            TextField(
                              enabled: !_settingUp,
                              controller: _wifiSsidCtrl!,
                              decoration: InputDecoration(
                                isDense: true,
                                errorText: _validSSID
                                    ? null
                                    : 'Please enter WiFi SSID',
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 20.0),
                              child: Text(
                                'WiFi Password',
                                style: TextStyle(fontSize: 16.0),
                              ),
                            ),
                            TextField(
                              enabled: !_settingUp,
                              controller: _wifiPassCtrl!,
                              obscureText: true,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: '(No Password)',
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  24.0, 24.0, 24.0, 12.0),
                              child: Center(
                                child: _settingUp
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(),
                                      )
                                    : SizedBox(
                                        width: 88,
                                        child: ElevatedButton(
                                          onPressed: () async => _setupSuccess
                                              ? Navigator.pushReplacementNamed(
                                                  context, RouteNames.home)
                                              : await _setup(),
                                          child: _setupSuccess
                                              ? Icon(Icons.arrow_forward)
                                              : Text(_retrySetup
                                                  ? 'Retry'
                                                  : 'Setup'),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_statusText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _statusText!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _settingUp
                                  ? Theme.of(context)
                                      .textTheme
                                      .bodyMedium!
                                      .color
                                  : _setupSuccess
                                      ? Colors.green
                                      : Colors.red,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
  }
}
