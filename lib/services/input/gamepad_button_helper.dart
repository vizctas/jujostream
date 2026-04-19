import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../preferences/launcher_preferences.dart';

class GamepadButtonHelper extends ChangeNotifier {
  GamepadButtonHelper._();
  static final instance = GamepadButtonHelper._();

  bool _ps = false;
  bool _hasGamepad = false;

  bool get isPlayStation => _ps;
  bool get hasGamepad => _hasGamepad;

  void init() {
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void dispose_() {
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  bool _onKey(KeyEvent ev) {

    final label = ev.physicalKey.debugName?.toLowerCase() ?? '';
    final wasPs = _ps;
    final wasGamepad = _hasGamepad;

    if (label.contains('playstation') || label.contains('sony') || label.contains('dualsense') || label.contains('dualshock')) {
      _ps = true;
      _hasGamepad = true;
    } else if (label.contains('xbox') || label.contains('microsoft')) {
      _ps = false;
      _hasGamepad = true;
    } else if (label.contains('gamepad') || label.contains('controller') || label.contains('joystick')) {
      _hasGamepad = true;
    }

    if (ev.logicalKey.debugName?.toLowerCase().startsWith('game button') == true) {
      _hasGamepad = true;
    }

    if (_ps != wasPs || _hasGamepad != wasGamepad) notifyListeners();
    return false;
  }

  void setPlayStation(bool value) {
    if (_ps == value) return;
    _ps = value;
    notifyListeners();
  }

  static const _xboxDir = 'assets/images/UI/xbox';
  static const _psDir = 'assets/images/UI/ps';
  static const _dirDir = 'assets/images/UI/directional';

  String _xb(String f) => '$_xboxDir/$f';
  String _ps_(String f) => '$_psDir/$f';
  String _dir(String f) => '$_dirDir/$f';

  String assetFor(String button, {String scheme = 'xbox'}) {
    final b = button.toUpperCase().replaceAll(' ', '');
    if (scheme == 'playstation') return _psAsset(b);
    return _xboxAsset(b);
  }

  String _xboxAsset(String b) {
    switch (b) {
      case 'A': case 'Ⓐ': return _xb('button_xbox_digital_a.png');
      case 'B': case 'Ⓑ': return _xb('button_xbox_digital_b.png');
      case 'X': case 'Ⓧ': return _xb('button_xbox_digital_x.png');
      case 'Y': case 'Ⓨ': return _xb('button_xbox_digital_y.png');
      case 'LB': case 'L1': return _xb('button_xbox_digital_bumper_lb.png');
      case 'RB': case 'R1': return _xb('button_xbox_digital_bumper_rb.png');
      case 'LT': case 'L2': return _xb('button_xbox_digital_bumper_LT.png');
      case 'RT': case 'R2': return _xb('button_xbox_digital_bumper_RT.png');
      case 'L3': case 'LS': return _xb('button_xboxone_digital_analog_ls.png');
      case 'R3': case 'RS': return _xb('button_xboxone_digital_analog_rs.png');
      case 'HOME': return _xb('button_xbox_digital_home.png');
      case 'SELECT': case 'BACK': return _xb('button_xbox_digital_select.png');
      case 'START': case 'MENU': return _xb('button_xbox_digital_start.png');
      case 'UP': case '↑': return _dir('up.png');
      case 'DOWN': case '↓': return _dir('down.png');
      case 'LEFT': case '◀': return _dir('left.png');
      case 'RIGHT': case '▶': return _dir('right.png');
      case '◀▶': return _dir('left.png');
      default: return _xb('button_xbox_digital_a.png');
    }
  }

  String _psAsset(String b) {
    switch (b) {
      case 'A': case 'Ⓐ': return _ps_('Button - PS Cross.png');
      case 'B': case 'Ⓑ': return _ps_('Button - PS Circle.png');
      case 'X': case 'Ⓧ': return _ps_('Button - PS Square.png');
      case 'Y': case 'Ⓨ': return _ps_('Button - PS Triangle.png');
      case 'LB': case 'L1': return _ps_('Button - PS L1.png');
      case 'RB': case 'R1': return _ps_('Button - PS R1.png');
      case 'LT': case 'L2': return _ps_('Button - PS L2.png');
      case 'RT': case 'R2': return _ps_('Button - PS R2.png');
      case 'L3': case 'LS': return _ps_('Button - PS L3.png');
      case 'R3': case 'RS': return _ps_('Button - PS R3.png');
      case 'HOME': return _ps_('Button - PS Home.png');
      case 'SELECT': case 'BACK': return _ps_('Button - PS Share.png');
      case 'START': case 'MENU': return _ps_('Button - PS Options.png');
      case 'UP': case '↑': return _dir('up.png');
      case 'DOWN': case '↓': return _dir('down.png');
      case 'LEFT': case '◀': return _dir('left.png');
      case 'RIGHT': case '▶': return _dir('right.png');
      case '◀▶': return _dir('left.png');
      default: return _ps_('Button - PS Cross.png');
    }
  }
}

class GamepadHintIcon extends StatelessWidget {
  final String button;
  final double size;
  final bool forceVisible;

  const GamepadHintIcon(this.button, {
    super.key,
    this.size = 25,
    this.forceVisible = false,
  });

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<LauncherPreferences>();
    if (!prefs.showButtonHints && !forceVisible) {
      return const SizedBox.shrink();
    }
    final asset = GamepadButtonHelper.instance.assetFor(button, scheme: prefs.buttonScheme);
    return Image.asset(asset, width: size, height: size, filterQuality: FilterQuality.medium);
  }
}

class GamepadDirectionalHint extends StatelessWidget {
  final double size;
  final bool forceVisible;

  const GamepadDirectionalHint({
    super.key,
    this.size = 20,
    this.forceVisible = false,
  });

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<LauncherPreferences>();
    if (!prefs.showButtonHints && !forceVisible) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/UI/directional/left.png', width: size, height: size, filterQuality: FilterQuality.medium),
        const SizedBox(width: 1),
        Image.asset('assets/images/UI/directional/right.png', width: size, height: size, filterQuality: FilterQuality.medium),
      ],
    );
  }
}
