import 'package:firebase_database/firebase_database.dart' show DatabaseEvent;

import 'package:fishmatic/backend/data_models.dart';
import 'package:fishmatic/backend/data_access.dart';
import 'package:fishmatic/backend/exceptions.dart';


abstract class _BaseServo {
  final GenericDAO<int> _dataAccess;

  _BaseServo(this._dataAccess);

  Future<void> initialise() async => _dataAccess.init(0);

  Future<void> executeCycle(
      int initAngle, int endAngle, int delaySeconds) async {
    await _dataAccess.setValue(initAngle);
    await Future.delayed(Duration(seconds: delaySeconds));
    await _dataAccess.setValue(endAngle);
  }
}

class Fishmatic {
  final String userID;
  late final Flag lightOn;
  late final Flag autoLightOn;
  late final FeederServo feederServo;
  late final FilterServo filterServo;
  late final StatusMonitor statusMonitor;
  late final ScheduleManager scheduleManager;

  Fishmatic(this.userID) {
    lightOn = Flag(GenericDAO<bool>(userID, DataNodes.lightOnFlag));
    autoLightOn = Flag(GenericDAO<bool>(userID, DataNodes.autoLightOn));
    feederServo = FeederServo(GenericDAO<int>(userID, DataNodes.feederServo));
    filterServo = FilterServo(GenericDAO<int>(userID, DataNodes.filterServo));
    statusMonitor = StatusMonitor(StatusDAO(userID));
    scheduleManager =
        ScheduleManager(ScheduleDAO(userID), Limits.scheduleLimit);
  }

  Future<void> initialise() async {
    await lightOn.initialise();
    await autoLightOn.initialise();
    await feederServo.initialise();
    await filterServo.initialise();
    await statusMonitor.initialise();
  }

  Future<void> feedFish(double amount, double currentLevel) async {
    if (currentLevel <= Limits.criticalLowFood) throw CriticalFoodException();
    await feederServo.executeFeedCycle();
    await statusMonitor.updateFoodLevel(currentLevel - amount);
  }

  Future<void> setAutoLight(bool enable, ValueStatus lightStatus) async {
    await autoLightOn.setFlag(enable);
    if (enable) await setLight(lightStatus);
  }

  Future<LightFlags> setLight(ValueStatus lightLevel,
      [bool? flag]) async {
    bool currLightOnFlag = await lightOn.flag;
    bool autoLightOnFlag = await autoLightOn.flag;
    if (autoLightOnFlag)
      await lightOn.setFlag(lightLevel == ValueStatus.criticalLow);
    else
      await lightOn.setFlag(flag ?? currLightOnFlag);
    return LightFlags(await lightOn.flag, autoLightOnFlag);
  }
}

class FeederServo extends _BaseServo {
  FeederServo(GenericDAO<int> dataAccess) : super(dataAccess);

  Future<void> executeFeedCycle() async {
    await super.executeCycle(180, 0, 2);
  }
}

class FilterServo extends _BaseServo {
  FilterServo(GenericDAO<int> dataAccess) : super(dataAccess);

  Future<void> executeFilterCycle() async {
    await super.executeCycle(180, 0, 4);
  }
}

class Flag {
  GenericDAO<bool> _dataAccess;
  Flag(this._dataAccess);

  Future<void> initialise() async => await this._dataAccess.init(false);

  Future<void> setFlag(bool state) async =>
      await this._dataAccess.setValue(state);

  Future<bool> get flag async => await _dataAccess.getValue();
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

  final String dataNode = 'Schedules';
  final int limit;
  final ScheduleDAO dataAccess;

  ScheduleManager(this.dataAccess, this.limit);

  Future<List<Schedule>> get schedules async {
    print('getting schedule list');
    return (await dataAccess.scheduleMap).values.toList();
  }

  Future<int> get numSchedules async => (await schedules).length;

  Future<Schedule> get activeSchedule async {
    Map _dataMap = await dataAccess.scheduleMap;
    String? _activeName = await dataAccess.activeName;
    return _activeName == null
        ? Schedule.nullSchedule()
        : (_dataMap)[_activeName];
  }

  Future<void> newSchedule(Schedule schedule) async {
    final Map<String, dynamic> _dataMap = await dataAccess.scheduleMap;
    if (_dataMap.keys.length == limit)
      throw MaxItemLimitException(dataNode, limit);
    if (await scheduleExists(schedule.name))
      throw DuplicateNameException(dataNode, schedule.name);
    await dataAccess.addSchedule(schedule);
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
        throw NotFoundException(dataNode, oldScheduleName);
      await deleteSchedule(oldScheduleName);
    } else {
      editFields[Schedule.stmLabel] =
          Schedule.getTime(editFields[Schedule.stmLabel]).toString();
      editFields[Schedule.etmLabel] =
          Schedule.getTime(editFields[Schedule.etmLabel]).toString();
      if (!(await scheduleExists(newScheduleName)))
        throw NotFoundException(dataNode, newScheduleName);
      await dataAccess.updateData(newScheduleName, editFields);
    }
  }

  Future<void> deleteSchedule(String dataName) async {
    final Map<String, Schedule> _dataMap = await dataAccess.scheduleMap;
    if (_dataMap.keys.length == 0) throw MinItemLimitException(dataNode, 1);
    if (!(await scheduleExists(dataName, _dataMap)))
      throw NotFoundException(dataNode, dataName);
    await dataAccess.deleteSchedule(dataName);
    await updateActive();
  }

  Future<void> changeActive(String dataName) async {
    await dataAccess.deleteActive();
    await dataAccess.addActive(dataName);
  }

  Future<void> updateActive() async {
    final List<Schedule> _dataList = await schedules;
    switch (_dataList.length) {
      case 0:
        await dataAccess.deleteActive();
        return;
      case 1:
        await changeActive(_dataList[0].name);
        return;
      default:
        return;
    }
  }

  Future<bool> scheduleExists(String dataName,
      [Map<String, Schedule>? dataMap]) async {
    final Map<String, Schedule> _dataMap =
        dataMap ?? await dataAccess.scheduleMap;
    return _dataMap.containsKey(dataName);
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
