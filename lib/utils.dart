import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;

class ButtonInfo {
  final String text;
  final VoidCallback onTap;
  final Color color;

  ButtonInfo(this.text, this.onTap, this.color);
}

AlertDialog errorAlert(
        {required String title, required String text, BuildContext? context}) =>
    AlertDialog(
      title: Text(
        title,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      content: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            text,
            style: TextStyle(fontSize: 14),
          ),
        ),
      ),
      actions: <Widget>[
        ElevatedButton(
          onPressed: () =>
              context == null ? SystemNavigator.pop() : Navigator.pop(context),
          child: Text(context == null ? 'Exit' : 'Close'),
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
    _info.add(ListTile(
      leading: entry.key,
      title: Text(
        entry.value,
        style: TextStyle(fontSize: 16),
      ),
      dense: true,
      visualDensity: VisualDensity(
          horizontal: VisualDensity.minimumDensity,
          vertical: VisualDensity.minimumDensity),
    ));
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
