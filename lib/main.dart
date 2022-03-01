import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:rxdart/rxdart.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import 'package:fishmatic/backend/data_models.dart';
import 'package:fishmatic/backend/exceptions.dart';
import 'package:fishmatic/backend/fishmatic.dart';
import 'package:fishmatic/schedule.dart';
import 'package:fishmatic/utils.dart';

// TODO: Exception handling (network errors, sign in errors, null data errors)

Future<Fishmatic> initFishmatic() async {
  // TODO: Check if firebase is initialised before initialising
  await Firebase.initializeApp();
  final FirebaseAuth _fbAuth = FirebaseAuth.instance;
  final User user = (await _fbAuth.signInAnonymously()).user!;
  final Fishmatic _fm = Fishmatic(user.uid);
  await _fm.initialise();
  return _fm;
}

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
  late Future<Fishmatic> _futureFM;

  @override
  void initState() {
    _futureFM = initFishmatic();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fishmatic',
      theme: ThemeData.dark(),
      darkTheme: ThemeData.dark(),
      debugShowCheckedModeBanner: true,
      home: FutureBuilder<Fishmatic>(
          future: _futureFM,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              print(snapshot.error.toString());
              return errorAlert(
                  title: 'Initialisation error',
                  text: snapshot.error.toString());
            } else if (snapshot.hasData) {
              final Fishmatic fishmatic = snapshot.data!;
              print('Signed in Anonymously as user ${fishmatic.userID}');
              return HomePage(
                title: 'Fishmatic',
                fishmatic: fishmatic,
              );
            } else {
              return Center(
                child: CircularProgressIndicator(),
              );
            }
          }),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key, required this.title, required this.fishmatic})
      : super(key: key);

  final String title;
  final Fishmatic fishmatic;

  @override
  _HomePageState createState() {
    return _HomePageState(fishmatic);
  }
}

class _HomePageState extends State<HomePage> {
  final double _gaugeHeight = 200;
  final Fishmatic _fishmatic;
  late final StatusMonitor _statusMonitor;
  late final ScheduleManager _scheduleManager;
  late final TextEditingController _foodCtrl;
  late Stream<List<StreamData>> _valuesStream;
  late Future<Schedule> _activeSchedule;
  ListTile? _tempNotif, _foodNotif;
  double _waterTemp = 0.0;
  double _foodLevel = 0.0;
  ValueStatus _lightLevelStatus = ValueStatus.normal;
  ValueStatus _waterTempStatus = ValueStatus.normal;
  ValueStatus _foodLevelStatus = ValueStatus.normal;

  _HomePageState(this._fishmatic) {
    _statusMonitor = _fishmatic.statusMonitor;
    _scheduleManager = _fishmatic.scheduleManager;
  }

  @override
  void initState() {
    _foodCtrl = TextEditingController();
    _initFutures();
    super.initState();
  }

  @override
  void dispose() {
    _foodCtrl.dispose();
    super.dispose();
  }

  void _initFutures() {
    _valuesStream = CombineLatestStream.combine3(
        _statusMonitor.getValueStream(
          DataNodes.waterTemp,
          maxWarning: Limits.highTemp,
          maxCritical: Limits.criticalHighTemp,
          minWarning: Limits.lowTemp,
          minCritical: Limits.criticalLowTemp,
        ),
        _statusMonitor.getValueStream(
          DataNodes.foodLevel,
          minWarning: Limits.lowFood,
          minCritical: Limits.criticalLowFood,
          isFoodLevel: true,
        ),
        _statusMonitor.getValueStream(
          DataNodes.lightLevel,
          minCritical: Limits.criticalLowLight.toDouble(),
          maxCritical: Limits.criticalHighLight.toDouble(),
        ),
        (StreamData a, StreamData b, StreamData c) => [a, b, c]);
    _activeSchedule = _scheduleManager.activeSchedule;
  }

  void _refresh() {
    setState((() => _initFutures()));
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

  @override
  Widget build(BuildContext context) {
    // TODO: Don't refresh if user dismisses dialog by tapping outside
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
          builder: (BuildContext context, BoxConstraints viewportConstraints) =>
              SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                StreamBuilder<List<StreamData>>(
                  stream: _valuesStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final StreamData _tempData = snapshot.data![0];
                      final StreamData _foodData = snapshot.data![1];
                      final StreamData _lightData = snapshot.data![2];
                      if (_tempData.value != null && _tempData.status != null) {
                        _waterTemp = _tempData.value!;
                        _waterTempStatus = _tempData.status!;
                        _updateTempNotif();
                        print(
                            'water temperature updated: ${_tempData.toString()}');
                      }
                      if (_foodData.value != null && _foodData.status != null) {
                        _foodLevel = _foodData.value!;
                        _foodLevelStatus = _foodData.status!;
                        _updateFoodNotif();
                        print('food level updated: ${_foodData.toString()}');
                      }
                      if (_lightData.value != null &&
                          _lightData.status != null) {
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
                                    padding:
                                        EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
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
                                    padding:
                                        EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
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
                          child: StatefulBuilder(builder:
                              (BuildContext context, StateSetter setState) {
                            return FutureBuilder<LightFlags>(
                                future: _fishmatic.setLight(_lightLevelStatus),
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
                                                height: 20,
                                                child:
                                                    LinearProgressIndicator(),
                                              )
                                            : Switch(
                                                value: lightOn,
                                                onChanged: autoLight
                                                    ? null
                                                    : (value) async {
                                                        await _fishmatic.setLight(
                                                            _lightLevelStatus,
                                                            value);
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
                                                  await _fishmatic.setAutoLight(
                                                      value!,
                                                      _lightLevelStatus);
                                                  setState(() {});
                                                },
                                        ),
                                      ),
                                      Flexible(
                                        flex: 2,
                                        fit: FlexFit.tight,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              4.0, 8.0, 8.0, 8.0),
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
                ),
                FutureBuilder<Schedule>(
                  future: _activeSchedule,
                  builder: (context, snapshot) {
                    print('current active: ${snapshot.data}');
                    late Widget _child;
                    switch (snapshot.connectionState) {
                      case ConnectionState.active:
                      case ConnectionState.waiting:
                        _child = Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
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
                              showDialog(
                                context: context,
                                builder: (_) => ScheduleDialog(
                                  _scheduleManager,
                                  initial: _active,
                                ),
                              ).then((_) {
                                // TODO: refresh only if schedule has been edited
                                _refresh();
                              });
                            }, Theme.of(context).colorScheme.primary),
                            ButtonInfo('Change', () {
                              showDialog(
                                context: context,
                                builder: (_) =>
                                    ScheduleListDialog(_scheduleManager),
                              ).then((_) {
                                // TODO: refresh only if schedule has been changed
                                _refresh();
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
                                padding: const EdgeInsets.only(
                                    left: 16.0, top: 16.0),
                                child: Row(
                                  children: <Widget>[
                                    Text(
                                      'Current Schedule',
                                      style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity(
                                          vertical:
                                              VisualDensity.minimumDensity),
                                      onPressed: () => _refresh(),
                                      icon: Icon(
                                        Icons.refresh,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
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
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: 'Actions',
        child: PopupMenuButton(
          offset: const Offset(0, -140),
          color: Theme.of(context).canvasColor,
          icon: Icon(Icons.more_horiz),
          onCanceled: () {},
          onSelected: (int option) {
            switch (option) {
              case 0:
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SchedulesPage(_scheduleManager),
                  ),
                ).then((_) {
                  _refresh();
                });
                break;
              case 1:
                showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      bool _validFood = true;
                      bool _isFeeding = false;
                      bool _done = false;
                      bool _fail = false;
                      String? _statusText;

                      return StatefulBuilder(
                        builder: (BuildContext context, StateSetter setState) =>
                            AlertDialog(
                          insetPadding: EdgeInsets.symmetric(
                              horizontal: 8.0, vertical: 24.0),
                          contentPadding:
                              EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0.0),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Text('Feed Fish'),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  children: <Widget>[
                                    Flexible(
                                      flex: 2,
                                      fit: FlexFit.loose,
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(right: 16.0),
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
                                    style: TextStyle(
                                        color:
                                            _done ? Colors.green : Colors.red),
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
                                              if (_foodCtrl.text.isEmpty ||
                                                  double.tryParse(
                                                          _foodCtrl.text) ==
                                                      null) _validFood = false;
                                            });
                                            if (_validFood) {
                                              FocusScopeNode _currentFocus =
                                                  FocusScope.of(context);
                                              if (!_currentFocus
                                                  .hasPrimaryFocus)
                                                _currentFocus.unfocus();
                                              setState(() => _isFeeding = true);
                                              try {
                                                await _fishmatic.feedFish(
                                                    double.parse(
                                                        _foodCtrl.text),
                                                    _foodLevel);
                                                setState(() {
                                                  _done = true;
                                                  _statusText =
                                                      'Feeding successful';
                                                });
                                              } on CriticalFoodException catch (e) {
                                                setState(() {
                                                  _fail = true;
                                                  _statusText = e.message;
                                                });
                                              }
                                            }
                                          },
                              ),
                            )
                          ],
                        ),
                      );
                    });
                break;
              default:
                DoNothingAction();
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
            PopupMenuItem<int>(
              value: 0,
              child: ListTile(
                leading: Icon(
                  Icons.calendar_today,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                title: Text('Schedules'),
              ),
            ),
            PopupMenuItem(
              value: 1,
              child: ListTile(
                leading: Icon(
                  Icons.fastfood,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                title: Text('Feed fish'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
