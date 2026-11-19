import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;

/// Address of my deployed API.
const String apiUrl = 'https://maize-yield-api-j1gx.onrender.com/predict';

void main() {
  runApp(const MaizeYieldApp());
}

class MaizeYieldApp extends StatelessWidget {
  const MaizeYieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maize Yield Predictor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const PredictionPage(),
    );
  }
}

/// A single input field: its name, label, hint and whether it must be a number.
class InputSpec {
  const InputSpec(this.key, this.label, this.hint, {this.isNumber = true});

  final String key;
  final String label;
  final String hint;
  final bool isNumber;
}

/// The 10 inputs, in the same order and with the same names as the API.
const List<InputSpec> inputs = [
  InputSpec('rainfall_mm', 'Season rainfall (mm)', '200 – 2500, e.g. 900'),
  InputSpec('avg_temp_c', 'Average temperature (°C)', '10 – 30, e.g. 20'),
  InputSpec('aridity_index', 'Aridity index', '0.3 – 3.0, e.g. 1.2 (higher = wetter)'),
  InputSpec('nitrogen_kg_ha', 'Nitrogen fertilizer (kg/ha)', '0 – 350, e.g. 40'),
  InputSpec('phosphorus_kg_ha', 'Phosphorus fertilizer (kg/ha)', '0 – 150, e.g. 20'),
  InputSpec('country', 'Country', 'Burundi, Kenya, Nigeria, Rwanda, Tanzania, Uganda or Zambia',
      isNumber: false),
  InputSpec('hybrid_seed', 'Hybrid seed planted?', 'yes or no', isNumber: false),
  InputSpec('pest_damage', 'Pest damage?', 'yes or no', isNumber: false),
  InputSpec('excess_water', 'Damage from too much rain?', 'yes or no', isNumber: false),
  InputSpec('fertilizer_in_hole', 'Fertilizer put in the planting hole?', 'yes or no',
      isNumber: false),
];

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  /// One controller per text field: it holds what the user typed.
  final Map<String, TextEditingController> _controllers = {
    for (final input in inputs) input.key: TextEditingController(),
  };

  bool _loading = false;
  String? _result;
  bool _isError = false; 

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Reads the 10 text fields and builds the request body
  /// 
  /// Missing values and numbers that are not numbers are added to [problems]
  Map<String, dynamic> _readInputs(List<String> problems) {
    final body = <String, dynamic>{};
    for (final input in inputs) {
      final text = _controllers[input.key]!.text.trim();
      if (text.isEmpty) {
        problems.add('${input.label} is missing.');
      } else if (input.isNumber) {
        final number = double.tryParse(text);
        if (number == null) {
          problems.add('${input.label} must be a number (you typed "$text").');
        } else {
          body[input.key] = number;
        }
      } else if (input.key == 'country') {
        // "rwanda" or "RWANDA" -> "Rwanda", the spelling the API expects
        body[input.key] = text[0].toUpperCase() + text.substring(1).toLowerCase();
      } else {
        body[input.key] = text.toLowerCase(); // "Yes" -> "yes"
      }
    }
    return body;
  }

  /// Sends the inputs to the API and shows the prediction or an error
  Future<void> _predict() async {
    FocusScope.of(context).unfocus(); // close the keyboard

    final problems = <String>[];
    final body = _readInputs(problems);
    if (problems.isNotEmpty) {
      _show(problems.join('\n'), isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tonnes = (data['predicted_yield_t_ha'] as num).toStringAsFixed(2);
        final kg = (data['predicted_yield_kg_ha'] as num).round();
        _show('Predicted maize yield:\n$tonnes tonnes per hectare\n(about $kg kg per hectare)',
            isError: false);
      } else if (response.statusCode == 422) {
        // The API returns a list of validation errors in the "detail" field of the JSON response.
        _show(_readableApiErrors(jsonDecode(response.body)['detail']), isError: true);
      } else {
        _show('The server returned an error (${response.statusCode}). Please try again.',
            isError: true);
      }
    } on TimeoutException {
      _show('The server took too long to answer. It may be waking up: please tap Predict again.',
          isError: true);
    } catch (e) {
      _show('Could not reach the server. Check your internet connection and try again.',
          isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Turns the API's validation errors (status 422) into readable sentences.
  String _readableApiErrors(dynamic detail) {
    if (detail is! List) return 'Some values are not valid. Please check your inputs.';
    final lines = <String>[];
    for (final error in detail) {
      final key = (error['loc'] as List).last.toString();
      final label = inputs
          .firstWhere((input) => input.key == key, orElse: () => InputSpec(key, key, ''))
          .label;
      lines.add('$label: ${error['msg']}.');
    }
    return lines.join('\n');
  }

  void _show(String message, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _result = message;
      _isError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maize Yield Predictor'),
        backgroundColor: colors.primaryContainer,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter the conditions of one maize field to predict its harvest.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              // One labelled text field per input variable (10 in total)
              for (final input in inputs) ...[
                TextField(
                  controller: _controllers[input.key],
                  keyboardType: input.isNumber
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: input.label,
                    helperText: input.hint,
                    helperMaxLines: 2,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              FilledButton(
                onPressed: _loading ? null : _predict,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Predict', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 16),
              _buildResultArea(colors),
            ],
          ),
        ),
      ),
    );
  }

  /// The display area that shows the prediction, an error, or a waiting message.
  Widget _buildResultArea(ColorScheme colors) {
    String text;
    IconData icon;
    Color background;
    Color foreground;

    if (_loading) {
      text = 'Predicting...\nThe first request can take up to a minute while the server wakes up.';
      icon = Icons.hourglass_top;
      background = colors.surfaceContainerHighest;
      foreground = colors.onSurfaceVariant;
    } else if (_result == null) {
      text = 'Your prediction will appear here.';
      icon = Icons.info_outline;
      background = colors.surfaceContainerHighest;
      foreground = colors.onSurfaceVariant;
    } else if (_isError) {
      text = _result!;
      icon = Icons.error_outline;
      background = colors.errorContainer;
      foreground = colors.onErrorContainer;
    } else {
      text = _result!;
      icon = Icons.agriculture;
      background = colors.primaryContainer;
      foreground = colors.onPrimaryContainer;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: foreground, fontSize: 16))),
        ],
      ),
    );
  }
}