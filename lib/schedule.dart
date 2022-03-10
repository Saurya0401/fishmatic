import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import 'package:fishmatic/backend/exceptions.dart';
import 'package:fishmatic/backend/fishmatic.dart';
import 'package:fishmatic/backend/data_models.dart' show Schedule, Timeouts;
import 'package:fishmatic/utils.dart';

class SchedulesPage extends StatefulWidget {
  const SchedulesPage(this._sManager, {Key? key}) : super(key: key);

  final ScheduleManager _sManager;

  @override
  _SchedulesPageState createState() => _SchedulesPageState(_sManager);
}

class _SchedulesPageState extends State<SchedulesPage> {
  late final ScheduleManager _sManager;
  late Future<List<Schedule>> _schedules;
  bool _refresh = true;

  _SchedulesPageState(ScheduleManager sManager) {
    _sManager = sManager;
  }

  @override
  void initState() {
    try {
      _schedules = _getSchedules();
    } on ConnectionTimeout catch (error) {
      print(error);
      showDialog(
          context: context,
          builder: (_) => errorAlert(error, context: context));
    }

    super.initState();
  }

  Future<List<Schedule>> _getSchedules() async {
    try {
      return await _sManager.schedules.timeout(Timeouts.cnxn,
          onTimeout: () =>
              throw ConnectionTimeout('Error retrieving schedules'));
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
            title: 'Server Error',
            message: 'Could not retrieve schedules. Please check your connection.',
            context: context,
          ),
        ),
      );
    }
    return [Schedule.nullSchedule()];
  }

  List<Card> _scheduleCards(List<Schedule> schedules) {
    List<Card> scheduleCards = [];
    for (Schedule schedule in schedules) {
      if (schedule.isNull) {
        scheduleCards = [
          Card(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error retrieving schedules.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        ];
        break;
      }
      scheduleCards.add(
        Card(
          child: infoList(schedule.name, {
            Icon(Icons.timer): schedule.intervalStr,
            Icon(Icons.fastfood): schedule.amountStr,
            Icon(Icons.timelapse): schedule.durationStr,
          }, <ButtonInfo>[
            ButtonInfo('Edit', () {
              showDialog(
                  context: context,
                  builder: (_) => ScheduleDialog(
                        _sManager,
                        initial: schedule,
                      )).then((_) {
                setState(() {});
              });
            }, Theme.of(context).colorScheme.primary),
            ButtonInfo('Delete', () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  bool _deleting = false;
                  return StatefulBuilder(
                    builder: (BuildContext context, StateSetter setState) =>
                        AlertDialog(
                      insetPadding: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 24.0),
                      contentPadding:
                          const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0.0),
                      title: Text('Delete Schedule'),
                      content: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                            'Are you sure you want to delete this schedule?'),
                      ),
                      actions: <Widget>[
                        TextButton(
                          child: Text('Cancel'),
                          onPressed: () => Navigator.pop(context),
                        ),
                        TextButton(
                          child: _deleting
                              ? Container(
                                  width: 22.0,
                                  height: 22.0,
                                  child: CircularProgressIndicator(),
                                )
                              : Text('Delete'),
                          onPressed: () async {
                            setState(() => _deleting = true);
                            try {
                              await _sManager.deleteSchedule(schedule.name);
                            } on MinItemLimitException catch (error) {
                              setState(() => _deleting = false);
                              showDialog(
                                  context: context,
                                  builder: (_) =>
                                      errorAlert(error, context: context));
                            } on NotFoundException catch (error) {
                              setState(() => _deleting = false);
                              showDialog(
                                  context: context,
                                  builder: (_) =>
                                      errorAlert(error, context: context));
                            }
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ).then((_) => setState(() {}));
            }, Colors.red)
          ]),
        ),
      );
    }
    return scheduleCards;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Schedules',
          style: TextStyle(
            fontSize: 25.0,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints viewportConstraints) =>
              SingleChildScrollView(
            child: FutureBuilder(
              future: _refresh ? _getSchedules() : _schedules,
              builder: (BuildContext context,
                  AsyncSnapshot<List<Schedule>> snapshot) {
                if (snapshot.hasError) {
                  print(snapshot.error);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _scheduleCards(snapshot.data!),
                  );
                } else if (snapshot.hasData) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _scheduleCards(snapshot.data!),
                  );
                } else {
                  return Center(
                    child: CircularProgressIndicator(),
                  );
                }
              },
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _refresh = false;
          showDialog(
              context: context,
              builder: (_) => ScheduleDialog(_sManager)).then((_) {
            _refresh = true;
            setState(() {});
          });
        },
        label: const Text('New Schedule'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class ScheduleDialog extends StatefulWidget {
  ScheduleDialog(this._sm, {Key? key, Schedule? initial}) : super(key: key) {
    _initial = initial;
  }

  final ScheduleManager _sm;
  late final Schedule? _initial;

  @override
  _ScheduleDialogState createState() => _ScheduleDialogState(_sm, _initial);
}

class _ScheduleDialogState extends State<ScheduleDialog> {
  final ScheduleManager _sm;
  final Schedule? _initial;
  late final TextEditingController _nameCtrl, _intervalCtrl, _foodCtrl;
  late String _startHour;
  late String _startMinute;
  late String _endHour;
  late String _endMinute;
  bool _addingSchedule = false;
  bool _validName = true, _validInterval = true, _validFood = true;

  _ScheduleDialogState(this._sm, this._initial);

  @override
  void initState() {
    _nameCtrl = TextEditingController(text: _initial?.name);
    _foodCtrl =
        TextEditingController(text: _initial?.amount.toStringAsFixed(1));
    _intervalCtrl =
        TextEditingController(text: _initial?.interval.toStringAsFixed(1));
    _startHour = _initial?.sTime.hour.toString().padLeft(2, '0') ?? '00';
    _startMinute = _initial?.sTime.minute.toString().padLeft(2, '0') ?? '00';
    _endHour = _initial?.eTime.hour.toString().padLeft(2, '0') ?? '00';
    _endMinute = _initial?.eTime.minute.toString().padLeft(2, '0') ?? '00';
    super.initState();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _foodCtrl.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 24.0),
      contentPadding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0.0),
      scrollable: true,
      title: Text(_initial == null ? 'New Schedule' : 'Edit Schedule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        flex: 1,
                        fit: FlexFit.loose,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16.0),
                          child: Icon(Icons.drive_file_rename_outline),
                        ),
                      ),
                      Flexible(
                        flex: 3,
                        fit: FlexFit.loose,
                        child: TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            hintText: 'Enter schedule name',
                            errorText:
                                _validName ? null : 'Please enter a valid name',
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        flex: 1,
                        fit: FlexFit.loose,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16.0),
                          child: Icon(Icons.timer),
                        ),
                      ),
                      Flexible(
                        flex: 3,
                        fit: FlexFit.loose,
                        child: TextField(
                          controller: _intervalCtrl,
                          decoration: InputDecoration(
                              hintText: 'Enter interval',
                              errorText: _validInterval
                                  ? null
                                  : 'Please enter a valid interval'),
                        ),
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        flex: 2,
                        fit: FlexFit.loose,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16.0),
                          child: Icon(Icons.timelapse),
                        ),
                      ),
                      Flexible(
                        flex: 2,
                        fit: FlexFit.loose,
                        child: DropdownButton(
                          value: _startHour,
                          // isDense: true,
                          menuMaxHeight: 200,
                          icon: Icon(Icons.arrow_drop_down),
                          items: ScheduleManager.scheduleHours
                              .map<DropdownMenuItem<String>>(
                                  (hour) => DropdownMenuItem<String>(
                                        value: hour,
                                        child: Text(hour),
                                      ))
                              .toList(growable: false),
                          onChanged: (String? hour) {
                            setState(() {
                              _startHour = hour!;
                            });
                          },
                        ),
                      ),
                      Flexible(
                        flex: 1,
                        fit: FlexFit.loose,
                        child: Text(' : '),
                      ),
                      Flexible(
                        flex: 2,
                        fit: FlexFit.loose,
                        child: DropdownButton(
                          value: _startMinute,
                          // isDense: true,
                          icon: Icon(Icons.arrow_drop_down),
                          items: ScheduleManager.scheduleMins
                              .map<DropdownMenuItem<String>>(
                                  (minute) => DropdownMenuItem<String>(
                                        value: minute,
                                        child: Text(minute),
                                      ))
                              .toList(growable: false),
                          onChanged: (String? minute) {
                            setState(() {
                              _startMinute = minute!;
                            });
                          },
                        ),
                      ),
                      Flexible(
                          flex: 2,
                          child: Padding(
                            padding:
                                const EdgeInsets.only(right: 8.0, left: 8.0),
                            child: Text('to'),
                          )),
                      Flexible(
                        flex: 2,
                        fit: FlexFit.loose,
                        child: DropdownButton(
                          value: _endHour,
                          // isDense: true,
                          menuMaxHeight: 200,
                          icon: Icon(Icons.arrow_drop_down),
                          items: ScheduleManager.scheduleHours
                              .map<DropdownMenuItem<String>>(
                                  (hour) => DropdownMenuItem<String>(
                                        value: hour,
                                        child: Text(hour),
                                      ))
                              .toList(growable: false),
                          onChanged: (String? hour) {
                            setState(() {
                              _endHour = hour!;
                            });
                          },
                        ),
                      ),
                      Flexible(flex: 1, fit: FlexFit.loose, child: Text(' : ')),
                      Flexible(
                        flex: 2,
                        fit: FlexFit.loose,
                        child: DropdownButton(
                          value: _endMinute,
                          // isDense: true,
                          icon: Icon(Icons.arrow_drop_down),
                          items: ScheduleManager.scheduleMins
                              .map<DropdownMenuItem<String>>(
                                  (minute) => DropdownMenuItem<String>(
                                        value: minute,
                                        child: Text(minute),
                                      ))
                              .toList(growable: false),
                          onChanged: (String? minute) {
                            setState(() {
                              _endMinute = minute!;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        flex: 1,
                        fit: FlexFit.loose,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16.0),
                          child: Icon(Icons.fastfood),
                        ),
                      ),
                      Flexible(
                        flex: 4,
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
                        flex: 2,
                        fit: FlexFit.loose,
                        child: TextButton(
                          onPressed: () {},
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text('Auto'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        ListTile(
          title: ElevatedButton(
            child: _addingSchedule
                ? Container(
                    height: 22.0,
                    child: CircularProgressIndicator(),
                  )
                : Text('Submit'),
            onPressed: _addingSchedule
                ? null
                : () async {
                    setState(() {
                      _validName = _validInterval = _validFood = true;
                      if (_nameCtrl.text.isEmpty ||
                          double.tryParse(_nameCtrl.text) != null)
                        _validName = false;
                      if (_intervalCtrl.text.isEmpty ||
                          double.tryParse(_intervalCtrl.text) == null)
                        _validInterval = false;
                      if (_foodCtrl.text.isEmpty ||
                          double.tryParse(_foodCtrl.text) == null)
                        _validFood = false;
                    });
                    if (_validName && _validInterval && _validFood) {
                      FocusScopeNode _currentFocus = FocusScope.of(context);
                      if (!_currentFocus.hasPrimaryFocus)
                        _currentFocus.unfocus();
                      setState(() => _addingSchedule = true);
                      try {
                        _initial == null
                            ? await _sm
                                .newSchedule(Schedule(
                                    _nameCtrl.text,
                                    double.parse(_intervalCtrl.text),
                                    double.parse(_foodCtrl.text),
                                    startTime: _startHour + ':' + _startMinute,
                                    endTime: _endHour + ':' + _endMinute))
                                .timeout(Timeouts.cnxn,
                                    onTimeout: () => throw ConnectionTimeout(
                                        'Failed to add schedule'))
                            : await _sm
                                .editSchedule(_nameCtrl.text, _initial!.name, {
                                Schedule.intLabel:
                                    double.parse(_intervalCtrl.text),
                                Schedule.amtLabel: double.parse(_foodCtrl.text),
                                Schedule.stmLabel:
                                    _startHour + ':' + _startMinute,
                                Schedule.etmLabel: _endHour + ':' + _endMinute,
                              }).timeout(Timeouts.cnxn,
                                    onTimeout: () => throw ConnectionTimeout(
                                        'Failed to edit schedule'));
                      } on DuplicateNameException catch (error) {
                        setState(() => _addingSchedule = false);
                        showDialog(
                            context: context,
                            builder: (_) =>
                                errorAlert(error, context: context));
                      } on MaxItemLimitException catch (error) {
                        setState(() => _addingSchedule = false);
                        showDialog(
                            context: context,
                            builder: (_) =>
                                errorAlert(error, context: context));
                      } on NotFoundException catch (error) {
                        setState(() => _addingSchedule = false);
                        showDialog(
                            context: context,
                            builder: (_) =>
                                errorAlert(error, context: context));
                      } on ConnectionTimeout catch (error) {
                        setState(() => _addingSchedule = false);
                        showDialog(
                            context: context,
                            builder: (_) =>
                                errorAlert(error, context: context));
                      }
                      Navigator.pop(context);
                    }
                  },
          ),
        ),
      ],
    );
  }
}

class ScheduleListDialog extends StatefulWidget {
  const ScheduleListDialog(this._sm, {Key? key}) : super(key: key);

  final ScheduleManager _sm;

  @override
  _ScheduleListDialogState createState() => _ScheduleListDialogState(_sm);
}

class _ScheduleListDialogState extends State<ScheduleListDialog> {
  final ScheduleManager _sm;
  bool _updating = false;

  _ScheduleListDialogState(this._sm);

  Future<List<SimpleDialogOption>> _scheduleListDialog() async {
    try {
      List<SimpleDialogOption> scheduleOptions = [];
      (await _sm.schedules.timeout(Timeouts.cnxn,
              onTimeout: () =>
                  throw ConnectionTimeout('Failed to retrieve schedules')))
          .forEach((schedule) {
        scheduleOptions.add(
          SimpleDialogOption(
            child: Text(
              schedule.name,
              style: _updating
                  ? TextStyle(color: Theme.of(context).disabledColor)
                  : Theme.of(context).primaryTextTheme.bodyMedium,
            ),
            onPressed: _updating
                ? null
                : () async {
                    setState(() => _updating = true);
                    try {
                      await _sm.changeActive(schedule.name);
                    } on ConnectionTimeout catch (error) {
                      showDialog(
                          context: context,
                          builder: (_) => errorAlert(
                                error,
                                context: context,
                              ));
                    }
                    Navigator.pop(context);
                  },
          ),
        );
      });
      return scheduleOptions;
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
            title: 'Server Error',
            message: 'Could not retrieve schedules. Please check your connection.',
            context: context,
          ),
        ),
      );
    }
    return [
      SimpleDialogOption(
        child: Text('Error retrieving schedules.'),
        onPressed: () => Navigator.pop(context),
      )
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _scheduleListDialog(),
        builder: (BuildContext context,
            AsyncSnapshot<List<SimpleDialogOption>> snapshot) {
          if (snapshot.hasError) {
            print(snapshot.error);
             return SimpleDialog(
              title: const Text('Select schedule'),
              children: snapshot.data!,
            );
          } else if (snapshot.hasData) {
            return SimpleDialog(
              title: const Text('Select schedule'),
              children: snapshot.data!,
            );
          } else {
            return SimpleDialog(
              title: const Text('Loading schedules...'),
              children: <SimpleDialogOption>[
                SimpleDialogOption(
                  child: CircularProgressIndicator(),
                ),
              ],
            );
          }
        });
  }
}
