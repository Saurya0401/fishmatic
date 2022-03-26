import 'package:flutter/material.dart';

import './backend/setup_mode.dart';
import './backend/data_models.dart';
import './backend/exceptions.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({Key? key}) : super(key: key);

  static const route = RouteNames.setup;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  DeviceDiscovery? _deviceDiscovery;
  SetupManager? _setupManager;
  TextEditingController? _wifiSsidCtrl, _wifiPassCtrl;
  TextEditingController? _userEmailCtrl, _userPassCtrl;
  String? _statusText;
  bool _settingUp = false;
  bool _validSSID = true;
  bool _validEmail = true;
  bool _validPass = true;
  bool _setupSuccess = false;

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
      bool keepScanning = true;
      try {
        if (_deviceDiscovery!.discoveryStarted)
          _deviceDiscovery!.restart();
        else
          _deviceDiscovery!.start();
        print('device discovery started');
        await Future.doWhile(() async {
          try {
            String espAddr = _deviceDiscovery!.devices
                .singleWhere((device) => device.name == 'ESP32FM')
                .address;
            _setupManager = SetupManager(espAddr);
            print('device found');
            return false;
          } on StateError {
            print('device not found');
            await Future.delayed(Duration(seconds: 5));
            return keepScanning;
          }
        }).timeout(
          Timeouts.discovery,
          onTimeout: () {
            keepScanning = false;
            throw SetupException('ESP32 not found');
          },
        );
        await _setupManager!.pairESP32().timeout(
              Timeouts.pairing,
              onTimeout: () =>
                  throw BluetoothConnectionError('ESP32 pairing timed out'),
            );
        await _setupManager!.connect().timeout(
              Timeouts.cnxn,
              onTimeout: () =>
                  throw BluetoothConnectionError('ESP32 connection timed out'),
            );
        await _setupManager!.transferCredentials(SetupCredential(
          _wifiSsidCtrl!.text,
          _wifiPassCtrl!.text,
          _userEmailCtrl!.text,
          _userPassCtrl!.text,
        ));
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
      } on Exception catch (error) {
        _showError('Error', error.toString());
      }
    }
  }

  void _showError(String errorType, String errorMessage) {
    setState(() {
      _settingUp = false;
      _setupSuccess = false;
      _statusText = '$errorType\n' + errorMessage;
    });
  }

  @override
  void initState() {
    _deviceDiscovery = DeviceDiscovery();
    _userEmailCtrl = TextEditingController();
    _userPassCtrl = TextEditingController();
    _wifiSsidCtrl = TextEditingController();
    _wifiPassCtrl = TextEditingController(text: '');
    super.initState();
  }

  @override
  void dispose() {
    _deviceDiscovery?.stop();
    _userEmailCtrl?.dispose();
    _userPassCtrl?.dispose();
    _wifiSsidCtrl?.dispose();
    _wifiPassCtrl?.dispose();
    _setupManager?.cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                            errorText:
                                _validEmail ? null : 'Please enter email'),
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
                            errorText:
                                _validPass ? null : 'Please enter password'),
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
                          errorText:
                              _validSSID ? null : 'Please enter WiFi SSID',
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
                        padding:
                            const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 12.0),
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
                                        : Text('Setup'),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_statusText != null)
                  Text(
                    _statusText!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _settingUp
                          ? Theme.of(context).textTheme.bodyMedium!.color
                          : _setupSuccess
                              ? Colors.green
                              : Colors.red,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
