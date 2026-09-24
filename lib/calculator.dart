import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Opens a compact calculator without taking the user away from their task.
Future<void> showCalculator(BuildContext context) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close calculator',
  barrierColor: Colors.black.withValues(alpha: .24),
  transitionDuration: const Duration(milliseconds: 180),
  pageBuilder: (_, _, _) => const SafeArea(
    child: Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: _CalculatorPanel(),
      ),
    ),
  ),
  transitionBuilder: (_, animation, _, child) => SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(.12, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
    child: FadeTransition(opacity: animation, child: child),
  ),
);

/// Shared state for the calculator so calculations and inputs persist
/// across popup dismissals, screen changes, and app sessions.
class CalculatorController with ChangeNotifier {
  static final CalculatorController instance = CalculatorController._();

  CalculatorController._() {
    _loadState();
  }

  String _display = '0';
  String _expression = '';
  double? _firstValue;
  String? _operation;
  bool _replaceDisplay = false;
  final List<String> _history = [];

  String get display => _display;
  String get expression => _expression;
  double? get firstValue => _firstValue;
  String? get operation => _operation;
  bool get replaceDisplay => _replaceDisplay;
  List<String> get history => List.unmodifiable(_history);

  double get _value => double.tryParse(_display) ?? 0;

  String _format(double value) {
    if (!value.isFinite) return 'Error';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(8)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  double _apply(double left, double right, String op) => switch (op) {
    '+' => left + right,
    '−' => left - right,
    '×' => left * right,
    '÷' => right == 0 ? double.nan : left / right,
    _ => right,
  };

  void inputNumber(String key) {
    if (_replaceDisplay || _display == 'Error') {
      _display = key == '.' ? '0.' : (key == '00' ? '0' : key);
      _replaceDisplay = false;
      if (_operation == null && _firstValue == null) {
        _expression = '';
      }
    } else if (key == '.') {
      if (!_display.contains('.')) {
        _display += '.';
      }
    } else if (key == '00') {
      if (_display != '0' && _display.length < 16) {
        _display += '00';
      }
    } else {
      if (_display.length < 16) {
        _display = _display == '0' ? key : _display + key;
      }
    }
    notifyListeners();
    _saveState();
  }

  void inputOperator(String key) {
    if (_display == 'Error') return;
    final current = _value;
    if (_operation != null && !_replaceDisplay && _firstValue != null) {
      final evaluated = _apply(_firstValue!, current, _operation!);
      final formatted = _format(evaluated);
      final formula =
          '${_format(_firstValue!)} $_operation ${_format(current)} =';
      _history.insert(0, '$formula $formatted');
      if (_history.length > 50) _history.removeLast();
      _display = formatted;
      _firstValue = evaluated.isFinite ? evaluated : null;
      _expression = '$formatted $key';
    } else {
      _firstValue = current;
      _expression = '${_format(current)} $key';
    }
    _operation = key;
    _replaceDisplay = true;
    notifyListeners();
    _saveState();
  }

  void equals() {
    if (_operation == null || _firstValue == null || _display == 'Error') return;
    final right = _value;
    final left = _firstValue!;
    final op = _operation!;
    final result = _apply(left, right, op);
    final formattedResult = _format(result);
    final formattedLeft = _format(left);
    final formattedRight = _format(right);
    final fullEquation = '$formattedLeft $op $formattedRight =';

    _display = formattedResult;
    _expression = fullEquation;
    _firstValue = null;
    _operation = null;
    _replaceDisplay = true;

    if (formattedResult != 'Error') {
      _history.insert(0, '$fullEquation $formattedResult');
      if (_history.length > 50) _history.removeLast();
    }
    notifyListeners();
    _saveState();
  }

  void backspace() {
    if (_display == 'Error' || _replaceDisplay) {
      _display = '0';
      _replaceDisplay = false;
    } else {
      _display =
          _display.length <= 1 ? '0' : _display.substring(0, _display.length - 1);
      if (_display == '-' || _display.isEmpty) _display = '0';
    }
    notifyListeners();
    _saveState();
  }

  void clear() {
    if (_firstValue != null && _operation != null) {
      if (_display != '0') {
        _display = '0';
        _replaceDisplay = false;
      } else {
        _firstValue = null;
        _operation = null;
        _expression = '';
        _replaceDisplay = false;
      }
    } else {
      _display = '0';
      _firstValue = null;
      _operation = null;
      _expression = '';
      _replaceDisplay = false;
    }
    notifyListeners();
    _saveState();
  }

  void clearAll() {
    _display = '0';
    _firstValue = null;
    _operation = null;
    _expression = '';
    _replaceDisplay = false;
    notifyListeners();
    _saveState();
  }

  void restoreHistory(String item) {
    final parts = item.split(' = ');
    if (parts.length == 2) {
      _expression = '${parts[0]} =';
      _display = parts[1];
    } else {
      _display = item;
      _expression = '';
    }
    _firstValue = null;
    _operation = null;
    _replaceDisplay = true;
    notifyListeners();
    _saveState();
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
    _saveState();
  }

  @visibleForTesting
  void resetForTesting() {
    _display = '0';
    _expression = '';
    _firstValue = null;
    _operation = null;
    _replaceDisplay = false;
    _history.clear();
    notifyListeners();
  }

  Future<void> _loadState() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/calculator_state.json');
      if (await file.exists()) {
        final text = await file.readAsString();
        final data = jsonDecode(text) as Map<String, dynamic>;
        _display = data['display'] as String? ?? '0';
        _expression = data['expression'] as String? ?? '';
        _firstValue = (data['firstValue'] as num?)?.toDouble();
        _operation = data['operation'] as String?;
        _replaceDisplay = data['replaceDisplay'] as bool? ?? false;
        if (data['history'] is List) {
          _history.clear();
          for (final item in data['history'] as List) {
            _history.add(item.toString());
          }
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveState() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/calculator_state.json');
      await file.writeAsString(
        jsonEncode({
          'display': _display,
          'expression': _expression,
          'firstValue': _firstValue,
          'operation': _operation,
          'replaceDisplay': _replaceDisplay,
          'history': _history,
        }),
      );
    } catch (_) {}
  }
}

class _CalculatorPanel extends StatefulWidget {
  const _CalculatorPanel();

  @override
  State<_CalculatorPanel> createState() => _CalculatorPanelState();
}

class _CalculatorPanelState extends State<_CalculatorPanel> {
  final CalculatorController _controller = CalculatorController.instance;
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final clearLabel = _controller.display == '0' ? 'AC' : 'C';

        return Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          elevation: 10,
          shadowColor: Colors.black26,
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 310,
            padding: const EdgeInsets.all(16),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.calculate_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _showHistory ? 'History' : 'Calculator',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (_controller.history.isNotEmpty)
                    IconButton(
                      tooltip: _showHistory
                          ? 'Show keypad'
                          : 'Previous calculations',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _showHistory = !_showHistory),
                      icon: Icon(
                        _showHistory ? Icons.dialpad : Icons.history,
                        size: 20,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Close calculator',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 18,
                      child: Text(
                        _controller.expression.isEmpty
                            ? ''
                            : _controller.expression,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: .72),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _controller.display,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_showHistory)
                SizedBox(
                  height: 262,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          itemCount: _controller.history.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _controller.history[index];
                            final parts = item.split(' = ');
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              title: Text(
                                parts.isNotEmpty ? parts[0] : item,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              trailing: Text(
                                parts.length > 1 ? '= ${parts[1]}' : '',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onTap: () {
                                _controller.restoreHistory(item);
                                setState(() => _showHistory = false);
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () {
                                _controller.clearHistory();
                                setState(() => _showHistory = false);
                              },
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 18,
                              ),
                              label: const Text('Clear history'),
                            ),
                          ),
                          Expanded(
                            child: FilledButton.tonal(
                              onPressed: () =>
                                  setState(() => _showHistory = false),
                              child: const Text('Keypad'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                for (final row in [
                  [clearLabel, '⌫', '÷', '×'],
                  ['7', '8', '9', '−'],
                  ['4', '5', '6', '+'],
                  ['1', '2', '3', '='],
                  ['0', '00', '.', '='],
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: row
                          .map(
                            (key) => Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                child: FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 46),
                                    padding: EdgeInsets.zero,
                                  ),
                                  onPressed: () {
                                    if (key == 'C') {
                                      _controller.clear();
                                    } else if (key == 'AC') {
                                      _controller.clearAll();
                                    } else if (key == '⌫') {
                                      _controller.backspace();
                                    } else if (key == '=') {
                                      _controller.equals();
                                    } else if (const ['+', '−', '×', '÷']
                                        .contains(key)) {
                                      _controller.inputOperator(key);
                                    } else {
                                      _controller.inputNumber(key);
                                    }
                                  },
                                  child: Text(
                                    key,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
            ],
          ),
        ),
      );
    },
    );
  }
}

