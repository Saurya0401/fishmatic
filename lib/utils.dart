import 'package:fishmatic/backend/exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

class ButtonInfo {
  final String text;
  final VoidCallback onTap;
  final Color color;

  ButtonInfo(this.text, this.onTap, this.color);
}

AlertDialog errorAlert(
  Object error, {
  String? title,
  String? message,
  BuildContext? context,
}) =>
    AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 24.0),
      contentPadding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0.0),
      title: Text(
        error is FishmaticBaseException ? error.title : title ?? 'Error',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.red,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            error is FishmaticBaseException
                ? error.errorText
                : message ?? error.toString(),
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
      actions: <Widget>[
        ListTile(
          title: ElevatedButton(
            onPressed: () => context == null
                ? SystemNavigator.pop()
                : Navigator.pop(context),
            child: Text(context == null ? 'Exit' : 'Close'),
          ),
        ),
      ],
    );

Column infoList(String name, Map<Icon, String> infoMap,
    [List<ButtonInfo>? buttonInfos]) {
  List<Widget> _info = [
    ListTile(
        title: Text(
      name,
      style: TextStyle(fontSize: 16),
    ))
  ];
  List<Widget> _buttons = [];
  infoMap.entries.forEach((entry) {
    _info.add(
      ListTile(
        leading: entry.key,
        title: Text(
          entry.value,
          style: TextStyle(fontSize: 16),
        ),
        dense: true,
        visualDensity: VisualDensity(
            horizontal: VisualDensity.minimumDensity,
            vertical: VisualDensity.minimumDensity),
      ),
    );
  });
  buttonInfos?.forEach((button) {
    _buttons.add(Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 8.0, 8.0),
      child: ElevatedButton(
        onPressed: () {
          button.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(button.text),
        ),
        style: ElevatedButton.styleFrom(primary: button.color),
      ),
    ));
  });
  _info.add(Row(
    mainAxisAlignment: MainAxisAlignment.start,
    children: _buttons,
  ));
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: _info,
  );
}
