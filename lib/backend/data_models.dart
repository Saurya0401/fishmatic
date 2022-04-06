import 'package:cloud_firestore/cloud_firestore.dart';

enum ValueStatus {
  normal,
  high,
  low,
  criticalHigh,
  criticalLow,
  lowFood,
  criticalLowFood,
}

class DataNodes {
  static const String lightOn = 'light_on';
  static const String autoLightOn = 'auto_light';
  static const String setupSensor = 'setup_sensor';
  static const String noCnxnSensor = 'no_cnxn_sensor';
  static const String setupActuator = 'setup_actuator';
  static const String noCnxnActuator = 'no_cnxn_actuator';
  static const String feederServo = 'feeder_servo';
  static const String filterServo = 'filter_servo';
  static const String foodLevel = 'food_level';
  static const String waterTemp = 'water_temp';
  static const String lightLevel = 'light_level';
}

class DeviceNames {
  static const String sensor = 'sensor';
  static const String actuator = 'actuator';
}

class Limits {
  static const int scheduleLimit = 5;
  static const int criticalLowLight = 1000;
  static const int criticalHighLight = 3000;
  static const double lowFood = 20.0;
  static const double criticalLowFood = 10.0;
  static const double lowTemp = 20.0;
  static const double criticalLowTemp = 15.0;
  static const double highTemp = 30.0;
  static const double criticalHighTemp = 35.0;
}

class RouteNames {
  static const String home = '/home';
  static const String login = '/login';
  static const String setup = '/setup';
}

class Timeouts {
  static const Duration cnxn = Duration(seconds: 30);
  static const Duration pairing = Duration(minutes: 1);
  static const Duration discovery = Duration(minutes: 2);
  static const Duration setupWait = Duration(minutes: 2);
  static const Duration checkSetup = Duration(minutes: 1);
  static const Duration enableSetup = Duration(seconds: 30);

  Duration timeout(int seconds) => Duration(seconds: seconds);
}

class FoodRecord {
  final double amount;

  FoodRecord(this.amount);

  FoodRecord.fromJson(Map<String, Object?> json)
      : this.amount = json['amount'] as double;

  Map<String, Object?> toJson() => {
        'timestamp': FieldValue.serverTimestamp(),
        'amount': amount,
      };
}

class LightFlags {
  final bool _lightOnFlag;
  final bool _autoLightOnFlag;

  const LightFlags(this._lightOnFlag, this._autoLightOnFlag);

  bool get lightOnFlag => _lightOnFlag;
  bool get autoLightOnFlag => _autoLightOnFlag;

  @override
  String toString() => 'light: $_lightOnFlag, auto: $_autoLightOnFlag';
}

class StreamData {
  final ValueStatus? _status;
  final double? _value;

  StreamData([this._status, this._value]);

  ValueStatus? get status => _status;
  double? get value => _value;

  @override
  String toString() => '$_status: $_value';
}

class Schedule {
  static const String intLabel = 'interval';
  static const String amtLabel = 'amount';
  static const String stmLabel = 'sTime';
  static const String etmLabel = 'eTime';

  final String name;
  late double interval;
  late double amount;
  late DateTime sTime;
  late DateTime eTime;
  bool isNull = false;

  static DateTime getTime(String strTime) {
    return DateTime.parse(
        DateTime.now().toString().split(' ')[0] + ' ' + strTime);
  }

  String get intervalStr =>
      'Feeding fish every ${interval.toStringAsFixed(1)} hours';

  String get amountStr =>
      'Dispensing ${amount.toStringAsFixed(1)} units of food';

  String get durationStr {
    if (sTime == eTime)
      return 'Active all day';
    else
      return 'Active from ${sTime.hour.toString().padLeft(2, '0')}:${sTime.minute.toString().padLeft(2, '0')} to ${eTime.hour.toString().padLeft(2, '0')}:${eTime.minute.toString().padLeft(2, '0')}';
  }

  Schedule(this.name, this.interval, this.amount,
      {String startTime = '00:00', String endTime = '00:00'}) {
    this.sTime = Schedule.getTime(startTime);
    this.eTime = Schedule.getTime(endTime);
  }

  Schedule.fromJson(this.name, Map<String, dynamic> json)
      : interval = json[Schedule.intLabel].toDouble(),
        amount = json[Schedule.amtLabel].toDouble(),
        sTime = DateTime.parse(json[Schedule.stmLabel]),
        eTime = DateTime.parse(json[Schedule.etmLabel]) {
    print('parsing Schedule from json');
  }

  Map<String, dynamic> toJson() => {
        Schedule.intLabel: interval,
        Schedule.amtLabel: amount,
        Schedule.stmLabel: sTime.toString(),
        Schedule.etmLabel: eTime.toString(),
      };

  Schedule.nullSchedule()
      : name = 'Null',
        interval = 0.0,
        amount = 0.0,
        sTime = DateTime.now(),
        eTime = DateTime.now() {
    isNull = true;
  }

  @override
  String toString() => 'Schedule<$name: $interval, $sTime, $eTime>';
}

class SetupCredential {
  static const String sep = ',';
  static const String end = ';';

  final String userEmail;
  final String userPass;
  final String wifiSSID;
  final String wifiPass;

  const SetupCredential(
      this.userEmail, this.userPass, this.wifiSSID, this.wifiPass);

  String get payload =>
      <String>[userEmail, userPass].join(sep) +
      end +
      <String>[wifiSSID, wifiPass].join(sep) +
      end +
      '\n';
}
