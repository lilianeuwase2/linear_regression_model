import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Address of my deployed API.
const String apiUrl = 'https://maize-yield-api-j1gx.onrender.com/predict';

const Color leaf = Color(0xFF2E6B34);
const Color ink = Color(0xFF1F2D1F);
const Color muted = Color(0xFF5B6B57);
const Color paper = Color(0xFFF8F6EC);
const Color line = Color(0xFFDCE3CF);
const Color maize = Color(0xFFF2B705);
const Color maizeLight = Color(0xFFFFF6D5);
const Color errorRed = Color(0xFFB42318);
const Color errorLight = Color(0xFFFDECEA);

///starting the app
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
      theme: ThemeData(
        useMaterial3: true,
        // primary is used by the Predict button, the focused field border and the cursor
        colorScheme: ColorScheme.fromSeed(seedColor: leaf).copyWith(
          primary: leaf,
          onPrimary: Colors.white,
          error: errorRed,
        ),
        scaffoldBackgroundColor: paper,
      ),
      home: const PredictionPage(),
    );
  }
}

/// describing the 10 input fields for the maize yield prediction.
/// A single input field: its name, label, hint, the card it is shown in,
/// and whether it must be a number.
class InputSpec {
  const InputSpec(this.key, this.label, this.hint, this.section, {this.isNumber = true});

  final String key;
  final String label;
  final String hint;
  final String section;
  final bool isNumber;
}

/// The cards on the page, in the order they are shown, each with its icon.
const Map<String, IconData> sections = {
  'Location': Icons.place_outlined,
  'Weather this season': Icons.wb_sunny_outlined,
  'Fertilizer': Icons.science_outlined,
  'Seed and damage': Icons.grass_outlined,
};

/// The 10 inputs, with the same names as the API.
const List<InputSpec> inputs = [
  InputSpec('country', 'Country', 'Burundi, Kenya, Nigeria, Rwanda, Tanzania, Uganda or Zambia',
      'Location', isNumber: false),
  InputSpec('rainfall_mm', 'Season rainfall (mm)', '200 – 2500, e.g. 900', 'Weather this season'),
  InputSpec('avg_temp_c', 'Average temperature (°C)', '10 – 30, e.g. 20', 'Weather this season'),
  InputSpec('aridity_index', 'Aridity index', '0.3 – 3.0, e.g. 1.2 (higher = wetter)',
      'Weather this season'),
  InputSpec('nitrogen_kg_ha', 'Nitrogen fertilizer (kg/ha)', '0 – 350, e.g. 40', 'Fertilizer'),
  InputSpec('phosphorus_kg_ha', 'Phosphorus fertilizer (kg/ha)', '0 – 150, e.g. 20', 'Fertilizer'),
  InputSpec('fertilizer_in_hole', 'Fertilizer put in the planting hole?', 'yes or no',
      'Fertilizer', isNumber: false),
  InputSpec('hybrid_seed', 'Hybrid seed planted?', 'yes or no', 'Seed and damage',
      isNumber: false),
  InputSpec('pest_damage', 'Pest damage?', 'yes or no', 'Seed and damage', isNumber: false),
  InputSpec('excess_water', 'Damage from too much rain?', 'yes or no', 'Seed and damage',
      isNumber: false),
];

///the page and its state
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
  String? _error; 
 double? _yieldPerHa; 
  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Reading the fields and checking for missing or invalid values.
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

  ///calling the API to get the prediction


  Future<void> _predict() async {
    FocusScope.of(context).unfocus(); // close the keyboard

    final problems = <String>[];
    final body = _readInputs(problems);
    if (problems.isNotEmpty) {
      _showError(problems.join('\n'));
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
        _showResult((data['predicted_yield_t_ha'] as num).toDouble());
      } else if (response.statusCode == 422) {
        // The API returns a list of validation errors in the "detail" field of the JSON response.
        _showError(_readableApiErrors(jsonDecode(response.body)['detail']));
      } else {
        _showError('The server returned an error (${response.statusCode}). Please try again.');
      }
    } on TimeoutException {
      _showError('The server took too long to answer. It may be waking up: please tap Predict again.');
    } catch (e) {
      _showError('Could not reach the server. Check your internet connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Turning API errors into readable messages
  String _readableApiErrors(dynamic detail) {
    if (detail is! List) return 'Some values are not valid. Please check your inputs.';
    final lines = <String>[];
    for (final error in detail) {
      final key = (error['loc'] as List).last.toString();
      final label = inputs
          .firstWhere((input) => input.key == key, orElse: () => InputSpec(key, key, '', ''))
          .label;
      lines.add('$label: ${error['msg']}.');
    }
    return lines.join('\n');
  }

  void _showResult(double yieldPerHa) {
    if (!mounted) return;
    setState(() {
      _yieldPerHa = yieldPerHa;
      _error = null;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _yieldPerHa = null;
    });
  }

  /// the layout of the page: the cards of text fields, the Predict button, and the result area.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maize Yield Predictor', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: leaf,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent, // stops the bar changing colour when scrolling
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter the conditions of one maize field to predict its harvest.',
                style: TextStyle(fontSize: 15, color: muted),
              ),
              const SizedBox(height: 16),
              // One card per section; inside it, one labelled text field per input (10 in total)
              for (final section in sections.entries)
                _buildSection(section.key, section.value, [
                  for (final input in inputs.where((spec) => spec.section == section.key))
                    _buildField(_controllers[input.key]!, input.label, input.hint,
                        isNumber: input.isNumber),
                ]),
              const SizedBox(height: 4),
              FilledButton(
                onPressed: _loading ? null : _predict,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Predict', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 16),
              _buildResultArea(),
            ],
          ),
        ),
      ),
    );
  }

  /// A white card with a small icon and title, holding a group of text fields.
  Widget _buildSection(String title, IconData icon, List<Widget> fields) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: leaf),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink)),
            ],
          ),
          ...fields,
        ],
      ),
    );
  }

  /// One labelled text field.
  Widget _buildField(TextEditingController controller, String label, String hint,
      {required bool isNumber}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: controller,
        keyboardType:
            isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          helperMaxLines: 2,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: line),
          ),
        ),
      ),
    );
  }

  /// The display area: a waiting message, an error, an empty hint, or the prediction.
  Widget _buildResultArea() {
    if (_loading) {
      return _messageBox(
        Icons.hourglass_top,
        'Predicting...\nThe first request can take up to a minute while the server wakes up.',
        background: Colors.white,
        foreground: muted,
      );
    }
    if (_error != null) {
      return _messageBox(Icons.error_outline, _error!,
          background: errorLight, foreground: errorRed);
    }
    if (_yieldPerHa == null) {
      return _messageBox(Icons.info_outline, 'Your prediction will appear here.',
          background: Colors.white, foreground: muted);
    }

    // We have a prediction: show it in tonnes and in kilograms per hectare.
    final perHa = _yieldPerHa!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: maizeLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: maize, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.agriculture, color: leaf),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Predicted maize yield', style: TextStyle(fontSize: 14, color: muted)),
                const SizedBox(height: 4),
                Text('${perHa.toStringAsFixed(2)} tonnes per hectare',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ink)),
                const SizedBox(height: 6),
                Text('About ${(perHa * 1000).round()} kg per hectare.',
                    style: const TextStyle(fontSize: 14, color: ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A simple box with an icon and a message (waiting, error or empty).
  Widget _messageBox(IconData icon, String text,
      {required Color background, required Color foreground}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line),
      ),
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
