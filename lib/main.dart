import 'package:fishmatic/account.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:rxdart/rxdart.dart' show CombineLatestStream;
import 'package:syncfusion_flutter_gauges/gauges.dart';

import './backend/data_models.dart';
import './backend/exceptions.dart';
import './backend/fishmatic.dart';
import './setup.dart';
import './schedule.dart';
import './utils.dart';

// TODO: Wrapper function for Exception handling (network, auth, null data)
// TODO: Email + password authentication

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FishmaticApp());
}

class FishmaticApp extends StatefulWidget {
  const FishmaticApp({Key? key}) : super(key: key);

  @override
  State<FishmaticApp> createState() => _FishmaticAppState();
}

class _FishmaticAppState extends State<FishmaticApp> {
  FirebaseAuth? _fbAuth;
  Future<bool>? _futureCheckSignedIn;

  Future<bool> _checkSignedIn() async {
    await Firebase.initializeApp();
    _fbAuth = FirebaseAuth.instance;
    return _fbAuth!.currentUser != null;
  }

  @override
  void initState() {
    _futureCheckSignedIn = _checkSignedIn();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fishmatic',
      theme: ThemeData.dark(),
      darkTheme: ThemeData.dark(),
      debugShowCheckedModeBanner: true,
      routes: <String, WidgetBuilder>{
        RouteNames.home: (_) => HomePage(),
        RouteNames.login: (_) => LoginPage(),
        RouteNames.setup: (_) => SetupPage(),
      },
      home: FutureBuilder<bool>(
          future: _futureCheckSignedIn,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              bool _loggedIn = snapshot.data!;
              print('logged ${_loggedIn ? 'in' : 'out'}');
              return _loggedIn ? HomePage() : LoginPage();
            }
            return Center(
              child: CircularProgressIndicator(),
            );
          }),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  final String title = 'Fishmatic';

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final double _gaugeHeight = 200;
  Future<bool>? _futureFismaticInitialised;
  FirebaseAuth? _fbAuth;
  Fishmatic? _fishmatic;
  StatusMonitor? _statusMonitor;
  ScheduleManager? _scheduleManager;
  TextEditingController? _foodCtrl;
  Stream<List<StreamData>>? _valuesStream;
  Stream<bool>? _setupMode;
  Future<Schedule>? _activeSchedule;
  ListTile? _tempNotif, _foodNotif;
  double _waterTemp = 0.0;
  double _foodLevel = 0.0;
  ValueStatus _lightLevelStatus = ValueStatus.normal;
  ValueStatus _waterTempStatus = ValueStatus.normal;
  ValueStatus _foodLevelStatus = ValueStatus.normal;

  @override
  void initState() {
    _fbAuth = FirebaseAuth.instance;
    _foodCtrl = TextEditingController();
    _futureFismaticInitialised = _initFishmatic();
    super.initState();
  }

  @override
  void dispose() {
    _foodCtrl?.dispose();
    super.dispose();
  }

  Future<bool> _initFishmatic() async {
    try {
      print('Logged in as user ${_fbAuth!.currentUser!.uid}');
      _fishmatic = Fishmatic(_fbAuth!.currentUser!.uid);
      await _fishmatic!.initialise().timeout(
            Timeouts.cnxn,
            onTimeout: () =>
                throw ConnectionTimeout('Server initialisation failed'),
          );
      _statusMonitor = _fishmatic!.statusMonitor;
      _scheduleManager = _fishmatic!.scheduleManager;
      print('Fishmatic, status monitor and schedule manager initialised.');
      _initFutures();
      return true;
    } on ConnectionTimeout catch (error) {
      Future.delayed(
        Duration.zero,
        () => showDialog(
          context: context,
          builder: (_) => errorAlert(error),
        ),
      );
    } on FirebaseException catch (error) {
      Future.delayed(
        Duration.zero,
        () => showDialog(
          context: context,
          builder: (_) => errorAlert(error,
              title: 'Server Error', message: 'Server initialisation failed'),
        ),
      );
    }
    return false;
  }

  Future<Schedule> _getActiveSchedule() async {
    try {
      return await _scheduleManager!.activeSchedule.timeout(Timeouts.cnxn,
          onTimeout: () =>
              throw ConnectionTimeout('Failed to retrieve active schedule'));
    } on ConnectionTimeout catch (error) {
      Future.delayed(
        Duration.zero,
        () => showDialog(
          context: context,
          builder: (_) => errorAlert(
            error,
            context: context,
          ),
        ),
      );
    } on FirebaseException catch (error) {
      Future.delayed(
        Duration.zero,
        () => showDialog(
          context: context,
          builder: (_) => errorAlert(
            error,
            title: "Server Error",
            context: context,
          ),
        ),
      );
    }
    return Schedule.nullSchedule();
  }

  void _initFutures() {
    _valuesStream = CombineLatestStream.combine3(
            _statusMonitor!.getValueStream(
              DataNodes.waterTemp,
              maxWarning: Limits.highTemp,
              maxCritical: Limits.criticalHighTemp,
              minWarning: Limits.lowTemp,
              minCritical: Limits.criticalLowTemp,
            ),
            _statusMonitor!.getValueStream(
              DataNodes.foodLevel,
              minWarning: Limits.lowFood,
              minCritical: Limits.criticalLowFood,
              isFoodLevel: true,
            ),
            _statusMonitor!.getValueStream(
              DataNodes.lightLevel,
              minCritical: Limits.criticalLowLight.toDouble(),
              maxCritical: Limits.criticalHighLight.toDouble(),
            ),
            (StreamData a, StreamData b, StreamData c) => [a, b, c])
        .asBroadcastStream();
    _activeSchedule = _getActiveSchedule();
    _setupMode = _fishmatic!.onSetupMode.asBroadcastStream();
  }

  void _refresh() {
    setState(() => _initFutures());
  }

  void _updateTempNotif() {
    switch (_waterTempStatus) {
      case ValueStatus.low:
      case ValueStatus.high:
        _tempNotif = _addNotif('Warning', 'Water temperature');
        break;
      case ValueStatus.criticalLow:
      case ValueStatus.criticalHigh:
        _tempNotif = _addNotif('Critical', 'Water temperature');
        break;
      default:
        _tempNotif = null;
        break;
    }
  }

  void _updateFoodNotif() {
    switch (_foodLevelStatus) {
      case ValueStatus.lowFood:
        _foodNotif = _addNotif('Warning', 'Food level');
        break;
      case ValueStatus.criticalLowFood:
        _foodNotif = _addNotif('Critical', 'Food level');
        break;
      default:
        _foodNotif = null;
        break;
    }
  }

  ListTile _addNotif(String title, String parameter) {
    String _statusText = () {
      switch (parameter) {
        case 'Water temperature':
          return '${_getStatusText(_waterTempStatus).toLowerCase()} ($_waterTemp \u2103).';
        case 'Food level':
          return '${_getStatusText(_foodLevelStatus).toLowerCase()}. ' +
              (_foodLevelStatus == ValueStatus.lowFood
                  ? 'Refill feeder.'
                  : 'Feeding suspended.');
        default:
          return '';
      }
    }();
    return _getNotifTile(title, '$parameter is $_statusText');
  }

  ListTile _getNotifTile(String title, String message) {
    final IconData _iconData = title == 'Warning' ? Icons.error : Icons.warning;
    final Color _iconColor = title == 'Warning' ? Colors.orange : Colors.red;
    return ListTile(
      leading: Icon(
        _iconData,
        color: _iconColor,
        size: 40.0,
      ),
      title: Text(
        title,
        style: TextStyle(color: _iconColor, fontSize: 14),
      ),
      subtitle: Text(
        message,
        style: TextStyle(fontSize: 14),
      ),
      dense: true,
    );
  }

  String _getStatusText(ValueStatus status) {
    switch (status) {
      case ValueStatus.normal:
        return 'Normal';
      case ValueStatus.high:
        return 'High';
      case ValueStatus.low:
      case ValueStatus.lowFood:
        return 'Low';
      case ValueStatus.criticalHigh:
        return 'Too High';
      case ValueStatus.criticalLow:
      case ValueStatus.criticalLowFood:
        return 'Too Low';
    }
  }

  Color _getStatusColor(ValueStatus status) {
    switch (status) {
      case ValueStatus.normal:
        return Colors.green;
      case ValueStatus.high:
      case ValueStatus.low:
      case ValueStatus.lowFood:
        return Colors.orange;
      case ValueStatus.criticalHigh:
      case ValueStatus.criticalLow:
      case ValueStatus.criticalLowFood:
        return Colors.red;
    }
  }

  SfRadialGauge _getRadialGauge(
      {required String title,
      required double value,
      required ValueStatus valueStatus,
      required double gaugeMin,
      required double gaugeMax,
      double? minWarning,
      double? maxWarning,
      double? minCritical,
      double? maxCritical,
      String? unit}) {
    // TODO: Compensate for values that overflow gauge limits
    final Color textColor = _getStatusColor(valueStatus);
    minWarning = minWarning ?? gaugeMin;
    minCritical = minCritical ?? minWarning;
    maxWarning = maxWarning ?? gaugeMax;
    maxCritical = maxCritical ?? maxWarning;
    return SfRadialGauge(
      title: GaugeTitle(
        text: title,
        textStyle: TextStyle(
          fontSize: 20,
        ),
      ),
      enableLoadingAnimation: true,
      axes: <RadialAxis>[
        RadialAxis(
          minimum: gaugeMin,
          maximum: gaugeMax,
          ranges: <GaugeRange>[
            GaugeRange(
              startValue: gaugeMin,
              endValue: minCritical,
              color: Colors.red,
            ),
            GaugeRange(
              startValue: minCritical,
              endValue: minWarning,
              color: Colors.orange,
            ),
            GaugeRange(
              startValue: minWarning,
              endValue: maxWarning,
              color: Colors.green,
            ),
            GaugeRange(
              startValue: maxWarning,
              endValue: maxCritical,
              color: Colors.orange,
            ),
            GaugeRange(
              startValue: maxCritical,
              endValue: gaugeMax,
              color: Colors.red,
            )
          ],
          pointers: <GaugePointer>[
            MarkerPointer(
              value: value,
              color: Colors.white,
              markerOffset: 5.5,
              markerType: MarkerType.triangle,
              markerHeight: 18,
              enableAnimation: true,
            ),
          ],
          annotations: <GaugeAnnotation>[
            GaugeAnnotation(
              widget: Container(
                child: Text(
                  value.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              angle: 90,
              positionFactor: 0,
            ),
            if (unit != null)
              GaugeAnnotation(
                widget: Container(
                  child: Text(
                    unit,
                    style: TextStyle(
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                angle: 90,
                positionFactor: 0.25,
              ),
          ],
        )
      ],
    );
  }

  StreamBuilder<List<StreamData>> _valuesStreamBuilder() {
    print('building values stream');
    return StreamBuilder<List<StreamData>>(
      stream: _valuesStream!,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final StreamData _tempData = snapshot.data![0];
          final StreamData _foodData = snapshot.data![1];
          final StreamData _lightData = snapshot.data![2];
          if (_tempData.value != null && _tempData.status != null) {
            _waterTemp = _tempData.value!;
            _waterTempStatus = _tempData.status!;
            _updateTempNotif();
            print('water temperature updated: ${_tempData.toString()}');
          }
          if (_foodData.value != null && _foodData.status != null) {
            _foodLevel = _foodData.value!;
            _foodLevelStatus = _foodData.status!;
            _updateFoodNotif();
            print('food level updated: ${_foodData.toString()}');
          }
          if (_lightData.value != null && _lightData.status != null) {
            _lightLevelStatus = _lightData.status!;
            print('light level updated: ${_lightData.toString()}');
          }
        } else if (snapshot.hasError) {
          print('Error: ${snapshot.error.toString()}');
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      flex: 1,
                      fit: FlexFit.loose,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
                        child: SizedBox(
                          height: _gaugeHeight,
                          child: _getRadialGauge(
                              title: 'Temperature',
                              value: _waterTemp,
                              valueStatus: _waterTempStatus,
                              gaugeMin: 10,
                              gaugeMax: 40,
                              minWarning: Limits.lowTemp,
                              minCritical: Limits.criticalLowTemp,
                              maxWarning: Limits.highTemp,
                              maxCritical: Limits.criticalHighTemp,
                              unit: '\u2103'),
                        ),
                      ),
                    ),
                    Flexible(
                      flex: 1,
                      fit: FlexFit.loose,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
                        child: SizedBox(
                          height: _gaugeHeight,
                          child: _getRadialGauge(
                            title: 'Food Level',
                            value: _foodLevel,
                            valueStatus: _foodLevelStatus,
                            gaugeMin: 0,
                            gaugeMax: 100,
                            minWarning: Limits.lowFood,
                            minCritical: Limits.criticalLowFood,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_tempNotif != null) _tempNotif!,
                if (_foodNotif != null) _foodNotif!,
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: StatefulBuilder(
                  builder: (BuildContext context, StateSetter setState) {
                return FutureBuilder<LightFlags>(
                    future: _fishmatic!.setLight(_lightLevelStatus),
                    builder: (context, snapshot) {
                      bool waiting = true;
                      bool lightOn = false;
                      bool autoLight = false;
                      if (snapshot.hasData) {
                        lightOn = snapshot.data!.lightOnFlag;
                        autoLight = snapshot.data!.autoLightOnFlag;
                        waiting = false;
                        print(snapshot.data);
                      }
                      return Row(
                        children: <Flexible>[
                          Flexible(
                            flex: 6,
                            fit: FlexFit.tight,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                'Lights',
                                style: TextStyle(
                                  fontSize: 20,
                                ),
                              ),
                            ),
                          ),
                          Flexible(
                            flex: 3,
                            fit: FlexFit.tight,
                            child: waiting
                                ? SizedBox(
                                    height: 4,
                                    child: LinearProgressIndicator(),
                                  )
                                : Switch(
                                    value: lightOn,
                                    onChanged: autoLight
                                        ? null
                                        : (value) async {
                                            await _fishmatic!.setLight(
                                                _lightLevelStatus, value);
                                            setState(() {});
                                          },
                                  ),
                          ),
                          Flexible(
                            flex: 1,
                            fit: FlexFit.tight,
                            child: Checkbox(
                              value: autoLight,
                              onChanged: waiting
                                  ? null
                                  : (value) async {
                                      await _fishmatic!.setAutoLight(
                                          value!, _lightLevelStatus);
                                      setState(() {});
                                    },
                            ),
                          ),
                          Flexible(
                            flex: 2,
                            fit: FlexFit.tight,
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(4.0, 8.0, 8.0, 8.0),
                              child: Text(
                                'Auto',
                                style: TextStyle(
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    });
              }),
            ),
          ],
        );
      },
    );
  }

  FutureBuilder<Schedule> _activeScheduleBuilder() {
    return FutureBuilder<Schedule>(
      future: _activeSchedule!,
      builder: (context, snapshot) {
        print('current active: ${snapshot.data}');
        late Widget _child;
        switch (snapshot.connectionState) {
          case ConnectionState.active:
          case ConnectionState.waiting:
            _child = Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
            break;
          case ConnectionState.none:
            break;
          case ConnectionState.done:
            final Schedule _active = snapshot.data!;
            if (_active.isNull) {
              _child = Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'No Active Schedule',
                  style: TextStyle(
                    fontSize: 20,
                  ),
                ),
              );
            } else {
              _child = infoList(_active.name, {
                Icon(Icons.timer): _active.intervalStr,
                Icon(Icons.fastfood): _active.amountStr,
                Icon(Icons.timelapse): _active.durationStr,
              }, <ButtonInfo>[
                ButtonInfo('Edit', () {
                  showDialog<bool>(
                    context: context,
                    builder: (_) => ScheduleDialog(
                      _scheduleManager!,
                      initial: _active,
                    ),
                  ).then((scheduleEdited) {
                    if (scheduleEdited ?? false) {
                      try {
                        _refresh();
                      } on ConnectionTimeout catch (error) {
                        showDialog(
                            context: context,
                            builder: (_) =>
                                errorAlert(error, context: context));
                      }
                    }
                  });
                }, Theme.of(context).colorScheme.primary),
                ButtonInfo('Change', () {
                  showDialog<bool>(
                    context: context,
                    builder: (_) => ScheduleListDialog(_scheduleManager!),
                  ).then((scheduleChanged) {
                    print(scheduleChanged);
                    if (scheduleChanged ?? false) {
                      try {
                        _refresh();
                      } on ConnectionTimeout catch (error) {
                        showDialog(
                            context: context,
                            builder: (_) =>
                                errorAlert(error, context: context));
                      }
                    }
                  });
                }, Theme.of(context).colorScheme.primary),
              ]);
            }
            break;
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(4.0, 8.0, 4.0, 0.0),
          child: Card(
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, top: 16.0),
                    child: Row(
                      children: <Widget>[
                        Text(
                          'Current Schedule',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity(
                              vertical: VisualDensity.minimumDensity),
                          onPressed: () {
                            try {
                              _refresh();
                            } on ConnectionTimeout catch (error) {
                              showDialog(
                                  context: context,
                                  builder: (_) =>
                                      errorAlert(error, context: context));
                            }
                          },
                          icon: Icon(
                            Icons.refresh,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _child,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  StatefulBuilder _feedDialog(BuildContext context) {
    bool _validFood = true;
    bool _isFeeding = false;
    bool _done = false;
    bool _fail = false;
    String? _statusText;

    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) => AlertDialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 24.0),
        contentPadding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0.0),
        title: Text('Feed Fish'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: <Widget>[
                  Flexible(
                    flex: 2,
                    fit: FlexFit.loose,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: Icon(Icons.fastfood),
                    ),
                  ),
                  Flexible(
                    flex: 10,
                    fit: FlexFit.loose,
                    child: TextField(
                      controller: _foodCtrl,
                      decoration: InputDecoration(
                          hintText: 'Enter food amount',
                          errorText: _validFood
                              ? null
                              : 'Please enter a valid amount'),
                    ),
                  ),
                  Flexible(
                    flex: 4,
                    fit: FlexFit.loose,
                    child: TextButton(
                      onPressed: () {},
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Center(
                          child: Text('Auto'),
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
                  style: TextStyle(color: _done ? Colors.green : Colors.red),
                ),
              ),
          ],
        ),
        actions: <Widget>[
          ListTile(
            title: ElevatedButton(
              style: ElevatedButton.styleFrom(
                primary: _done
                    ? Colors.green
                    : Theme.of(context).colorScheme.primary,
              ),
              child: (_done || _fail)
                  ? Text(
                      'Close',
                      style: TextStyle(fontSize: 16),
                    )
                  : _isFeeding
                      ? Container(
                          width: 22.0,
                          height: 22.0,
                          child: CircularProgressIndicator(),
                        )
                      : Text(
                          'Dispense',
                          style: TextStyle(fontSize: 16),
                        ),
              onPressed: (_done || _fail)
                  ? () => Navigator.pop(context)
                  : _isFeeding
                      ? null
                      : () async {
                          setState(() {
                            _validFood = true;
                            if (_foodCtrl!.text.isEmpty ||
                                double.tryParse(_foodCtrl!.text) == null)
                              _validFood = false;
                          });
                          if (_validFood) {
                            FocusScopeNode _currentFocus =
                                FocusScope.of(context);
                            if (!_currentFocus.hasPrimaryFocus)
                              _currentFocus.unfocus();
                            setState(() => _isFeeding = true);
                            try {
                              await _fishmatic!
                                  .feedFish(
                                      double.parse(_foodCtrl!.text), _foodLevel)
                                  .timeout(Timeouts.cnxn,
                                      onTimeout: () => throw ConnectionTimeout(
                                          'Fish feeding failed.'));
                              setState(() {
                                _done = true;
                                _statusText = 'Feeding successful';
                              });
                            } on CriticalFoodException catch (e) {
                              setState(() {
                                _fail = true;
                                _statusText = e.errorText;
                              });
                            } on ConnectionTimeout catch (e) {
                              setState(() {
                                _fail = true;
                                _statusText = e.errorText;
                              });
                            }
                          }
                        },
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _futureFismaticInitialised!,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // TODO: Add button to try reloading
          print(snapshot.error.toString());
          return Center(
            child: Card(
              child: Text(snapshot.error.toString()),
            ),
          );
        } else if (snapshot.hasData) {
          if (snapshot.data!) {
            return StreamBuilder<bool>(
                stream: _setupMode,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    if (snapshot.data != null) {
                      bool onSetupMode = snapshot.data!;
                      return Scaffold(
                        appBar: AppBar(
                          title: Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 25.0,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          centerTitle: true,
                        ),
                        body: SafeArea(
                          child: LayoutBuilder(
                            builder: (BuildContext context,
                                    BoxConstraints viewportConstraints) =>
                                SingleChildScrollView(
                              child: onSetupMode
                                  ? Center(
                                      child: Column(
                                        children: <Widget>[
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 32.0,
                                                horizontal: 16.0),
                                            child: Text(
                                              'Setup Required',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge,
                                            ),
                                          ),
                                          SizedBox(
                                            width: 250,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 32.0,
                                                      horizontal: 16.0),
                                              child: Text(
                                                'Your fish feeder needs to be set up for full functionality.',
                                                style: TextStyle(fontSize: 16),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                24.0, 0.0, 24.0, 24.0),
                                            child: ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.popAndPushNamed(
                                                      context,
                                                      RouteNames.setup),
                                              child: Text('Proceed'),
                                            ),
                                          )
                                        ],
                                      ),
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        _valuesStreamBuilder(),
                                        _activeScheduleBuilder(),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        floatingActionButton: FloatingActionButton(
                          onPressed: () {},
                          tooltip: 'Actions',
                          child: PopupMenuButton(
                            offset: Offset(0, onSetupMode? -90: -190),
                            color: Theme.of(context).canvasColor,
                            icon: Icon(Icons.more_horiz),
                            onCanceled: () {},
                            onSelected: (int option) {
                              switch (option) {
                                case 0:
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          SchedulesPage(_scheduleManager!),
                                    ),
                                  ).then((_) {
                                    try {
                                      _refresh();
                                    } on ConnectionTimeout catch (error) {
                                      showDialog(
                                          context: context,
                                          builder: (_) => errorAlert(error,
                                              context: context));
                                    }
                                  });
                                  break;
                                case 1:
                                  showDialog(
                                    context: context,
                                    builder: _feedDialog,
                                  );
                                  break;
                                case 2:
                                  // TODO: set individual streams to null
                                  // TODO: or cancel streams by removing corresponding widget from widget tree
                                  _valuesStream = null;
                                  _fbAuth!
                                      .signOut()
                                      .then((_) => Navigator.popAndPushNamed(
                                            context,
                                            '/login',
                                          ));
                                  break;
                                default:
                                  DoNothingAction();
                              }
                            },
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<int>>[
                              if (!onSetupMode) PopupMenuItem<int>(
                                value: 0,
                                child: ListTile(
                                  leading: Icon(
                                    Icons.calendar_today,
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                  ),
                                  title: Text('Schedules'),
                                ),
                              ),
                              if (!onSetupMode) PopupMenuItem(
                                value: 1,
                                child: ListTile(
                                  leading: Icon(
                                    Icons.fastfood,
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                  ),
                                  title: Text('Feed fish'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 2,
                                child: ListTile(
                                  leading: Icon(
                                    Icons.logout,
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                  ),
                                  title: Text('Log out'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  }
                  return Center(
                    child: CircularProgressIndicator(),
                  );
                });
          }
        }
        return Center(
          child: CircularProgressIndicator(),
        );
      },
    );
  }
}
