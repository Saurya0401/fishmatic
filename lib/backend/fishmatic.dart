import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:firebase_database/firebase_database.dart' show DatabaseEvent;

import './data_models.dart';
import './data_access.dart';
import './exceptions.dart';

class Fishmatic {
  final String userID;
  late final Flag lightOn;
  late final Flag autoLightOn;
  late final Flag setupMode;
  late final Flag noConnection;
  late final Servo feederServo;
  late final Servo filterServo;
  late final StatusMonitor statusMonitor;
  late final ScheduleManager scheduleManager;
  late final FoodRecordsManager foodRecordsManager;

  Stream<bool> get onSetupMode => setupMode.flagStream;
  Stream<bool> get notConnected => noConnection.flagStream;

  Fishmatic(this.userID) {
    lightOn = Flag(GenericDAO<bool>(userID, DataNodes.lightOn));
    autoLightOn = Flag(GenericDAO<bool>(userID, DataNodes.autoLightOn));
    noConnection = Flag(GenericDAO<bool>(userID, DataNodes.noConnection), true);
    setupMode = Flag(GenericDAO<bool>(userID, DataNodes.setupMode), true);
    feederServo = Servo(GenericDAO<int>(userID, DataNodes.feederServo));
    filterServo = Servo(GenericDAO<int>(userID, DataNodes.filterServo));
    statusMonitor = StatusMonitor(StatusDAO(userID));
    scheduleManager =
        ScheduleManager(ScheduleDAO(userID), Limits.scheduleLimit);
    foodRecordsManager = FoodRecordsManager(FoodRecordDAO(userID));
  }

  Future<void> initialise() async {
    await lightOn.initialise();
    await autoLightOn.initialise();
    await noConnection.initialise();
    await setupMode.initialise();
    await feederServo.initialise();
    await filterServo.initialise();
    await statusMonitor.initialise();
  }

  Stream<bool> checkLoggedIn(FirebaseAuth firebaseAuth) {
    return firebaseAuth
        .authStateChanges()
        .map((user) => user == null ? false : true);
  }

  Future<void> testConnection() async {
    print('checking connection...');
    await noConnection.setFlag(true);
    Timer(Timeouts.enableSetup, () async {
      if (await noConnection.flag) {
        await setupMode.setFlag(true);
        print('ESP32 in setup mode');
      }
    });
  }

  Future<void> feedFish(double amount, double currentLevel) async {
    if (currentLevel <= Limits.criticalLowFood) throw CriticalFoodException();
    await feederServo.executeCycle(180, 0, 2);
    await foodRecordsManager.addRecord(amount);
    await statusMonitor.updateFoodLevel(currentLevel - amount);
  }

  Future<void> setAutoLight(bool enable, ValueStatus lightStatus) async {
    await autoLightOn.setFlag(enable);
    if (enable) await setLight(lightStatus);
  }

  Future<LightFlags> setLight(ValueStatus lightLevel, [bool? flag]) async {
    bool currLightOnFlag = await lightOn.flag;
    bool autoLightOnFlag = await autoLightOn.flag;
    if (autoLightOnFlag)
      await lightOn.setFlag(lightLevel == ValueStatus.criticalLow);
    else
      await lightOn.setFlag(flag ?? currLightOnFlag);
    return LightFlags(await lightOn.flag, autoLightOnFlag);
  }
}

class Flag {
  final bool _defaultState;
  final GenericDAO<bool> _dataAccess;
  const Flag(this._dataAccess, [this._defaultState = false]);

  Future<void> initialise() async => await this._dataAccess.init(_defaultState);

  Future<void> setFlag(bool state) async =>
      await this._dataAccess.setValue(state);

  Future<bool> get flag async => await _dataAccess.getValue();
  Stream<bool> get flagStream =>
      _dataAccess.getStream().map((event) => event.snapshot.value == null
          ? _defaultState
          : event.snapshot.value! as bool);
}

class FoodRecordsManager {
  final FoodRecordDAO _dataAccess;

  FoodRecordsManager(this._dataAccess);

  Future<void> addRecord(double amount) async =>
      await _dataAccess.addRecord(amount);

  Future<void> deleteRecords() async => await _dataAccess.deleteAllRecords();

  Future<double> calcOptimalAmount() async {
    List<double> amounts = await _dataAccess.getRecords();
    print(amounts);
    if (amounts.isEmpty) return 0;
    return amounts.reduce((a, b) => a + b) / amounts.length;
  }
}

class Servo {
  final GenericDAO<int> _dataAccess;

  Servo(this._dataAccess);

  Future<void> initialise() async => _dataAccess.init(0);

  Future<void> executeCycle(
      int startAngle, int endAngle, int delaySeconds) async {
    await _dataAccess.setValue(startAngle);
    await Future.delayed(Duration(seconds: delaySeconds));
    await _dataAccess.setValue(endAngle);
  }
}

class ScheduleManager {
  static final List<String> scheduleHours =
      List.generate(24, (index) => index.toString().padLeft(2, '0'));

  static final List<String> scheduleMins = List.generate(4, (index) {
    switch (index) {
      case 0:
        return '0'.padLeft(2, '0');
      case 1:
        return '15';
      case 2:
        return '30';
      case 3:
        return '45';
      default:
        return index.toString().padLeft(2, '0');
    }
  });

  final String dataNodeLabel = 'Schedules';
  final int _limit;
  final ScheduleDAO _dataAccess;

  ScheduleManager(this._dataAccess, this._limit);

  Future<List<Schedule>> get schedules async {
    print('getting schedule list');
    return (await _dataAccess.scheduleMap).values.toList();
  }

  Future<int> get numSchedules async => (await schedules).length;

  Future<Schedule> get activeSchedule async {
    Map _dataMap = await _dataAccess.scheduleMap;
    String? _activeName = await _dataAccess.activeName;
    return _activeName == null
        ? Schedule.nullSchedule()
        : (_dataMap)[_activeName];
  }

  Future<void> newSchedule(Schedule schedule) async {
    final Map<String, dynamic> _dataMap = await _dataAccess.scheduleMap;
    if (_dataMap.keys.length == _limit)
      throw MaxItemLimitException(dataNodeLabel, _limit);
    if (await scheduleExists(schedule.name))
      throw DuplicateNameException(dataNodeLabel, schedule.name);
    await _dataAccess.addSchedule(schedule);
    await updateActive();
  }

  Future<void> editSchedule(String newScheduleName, String oldScheduleName,
      Map<String, dynamic> editFields) async {
    if (newScheduleName != oldScheduleName) {
      await newSchedule(Schedule(newScheduleName, editFields[Schedule.intLabel],
          editFields[Schedule.amtLabel],
          startTime: editFields[Schedule.stmLabel],
          endTime: editFields[Schedule.etmLabel]));
      if ((await activeSchedule).name == oldScheduleName)
        await changeActive(newScheduleName);
      if (!(await scheduleExists(oldScheduleName)))
        throw NotFoundException(dataNodeLabel, oldScheduleName);
      await deleteSchedule(oldScheduleName);
    } else {
      editFields[Schedule.stmLabel] =
          Schedule.getTime(editFields[Schedule.stmLabel]).toString();
      editFields[Schedule.etmLabel] =
          Schedule.getTime(editFields[Schedule.etmLabel]).toString();
      if (!(await scheduleExists(newScheduleName)))
        throw NotFoundException(dataNodeLabel, newScheduleName);
      await _dataAccess.updateData(newScheduleName, editFields);
    }
  }

  Future<void> deleteSchedule(String scheduleName) async {
    final Map<String, Schedule> _scheduleMap = await _dataAccess.scheduleMap;
    if (_scheduleMap.keys.length == 0)
      throw MinItemLimitException(dataNodeLabel, 1);
    if (!(await scheduleExists(scheduleName, _scheduleMap)))
      throw NotFoundException(dataNodeLabel, scheduleName);
    await _dataAccess.deleteSchedule(scheduleName);
    await updateActive();
  }

  Future<void> changeActive(String scheduleName) async =>
      await _dataAccess.addActive(scheduleName);

  Future<void> updateActive() async {
    final List<Schedule> scheduleList = await schedules;
    switch (scheduleList.length) {
      case 0:
        await _dataAccess.deleteActive();
        return;
      case 1:
        await changeActive(scheduleList[0].name);
        return;
      default:
        return;
    }
  }

  Future<bool> scheduleExists(String scheduleName,
      [Map<String, Schedule>? scheduleMap]) async {
    final Map<String, Schedule> _scheduleMap =
        scheduleMap ?? await _dataAccess.scheduleMap;
    return _scheduleMap.containsKey(scheduleName);
  }
}

class StatusMonitor {
  final StatusDAO _dataAccess;

  StatusMonitor(this._dataAccess);

  Future<void> initialise() async {
    await _dataAccess.init(0.0, DataNodes.waterTemp);
    await _dataAccess.init(0.0, DataNodes.foodLevel);
    await _dataAccess.init(0, DataNodes.lightLevel);
  }

  Stream<StreamData> getValueStream(
    String dataNode, {
    double? maxWarning,
    double? minWarning,
    double? maxCritical,
    double? minCritical,
    bool isFoodLevel = false,
  }) {
    final Stream<DatabaseEvent> _stream = _dataAccess.getStatusStream(dataNode);
    return _stream.map<StreamData>((DatabaseEvent event) {
      if (event.snapshot.value == null) return StreamData();
      final double _value = double.parse(event.snapshot.value!.toString());
      if (maxCritical != null && _value >= maxCritical)
        return StreamData(ValueStatus.criticalHigh, _value);
      if (maxWarning != null && _value >= maxWarning)
        return StreamData(ValueStatus.high, _value);
      if (minCritical != null && _value <= minCritical)
        return StreamData(
            isFoodLevel ? ValueStatus.criticalLowFood : ValueStatus.criticalLow,
            _value);
      if (minWarning != null && _value <= minWarning)
        return StreamData(
            isFoodLevel ? ValueStatus.lowFood : ValueStatus.low, _value);
      return StreamData(ValueStatus.normal, _value);
    }).asBroadcastStream();
  }

  Future<void> updateFoodLevel(double level) async =>
      await _dataAccess.setChildValue(DataNodes.foodLevel, level);
}
