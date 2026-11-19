// AI settings: provider (OpenRouter / OpenAI), key entry (masked), model,
// save, and a live connection test.
import 'package:flutter/material.dart';

import '../../db.dart';
import '../../services/openai.dart';
import '../../theme.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});
  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _keyController = TextEditingController();
  final _modelController = TextEditingController();
  String _provider = 'openrouter';
  bool _obscure = true;
  bool _testing = false;
  String? _testResult; // null = not run, otherwise message

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await Db.getSetting('openai_key') ?? '';
    final provider = await Db.getSetting('ai_provider') ?? 'openrouter';
    final model = await Db.getSetting('ai_model') ?? Ai.defaultModel;
    if (!mounted) return;
    setState(() {
      _keyController.text = key;
      _provider = provider;
      _modelController.text = model;
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    await Db.setSetting('openai_key', key);
    await Db.setSetting('ai_provider', _provider);
    await Db.setSetting('ai_model', _modelController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(key.isEmpty ? 'Key cleared' : 'Settings saved')));
  }

  Future<void> _test() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _testResult = 'Enter a key first.');
      return;
    }
    await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final cfg = await Ai.config();
    final food = await Ai.createFoodFromDescription(cfg, 'apple');
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = (food != null && food.name.isNotEmpty)
          ? 'Connection OK — AI returned "${food.name}".'
          : 'Test failed — check the key, model id and your network.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ok = _testResult != null && _testResult!.startsWith('Connection OK');
    return Scaffold(
      appBar: AppBar(title: const Text('AI settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Your API key powers AI meal parsing, recipe import and custom '
            'food creation. It is stored on this device only and sent solely '
            'to the chosen provider (openrouter.ai or api.openai.com).',
            style: TextStyle(color: MtTheme.textDim, fontSize: 13),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'openrouter',
                  label: Text('OpenRouter'),
                  icon: Icon(Icons.route, size: 18)),
              ButtonSegment(
                  value: 'openai',
                  label: Text('OpenAI'),
                  icon: Icon(Icons.diamond_outlined, size: 18)),
            ],
            selected: {_provider},
            onSelectionChanged: (s) => setState(() => _provider = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _keyController,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: _provider == 'openrouter'
                  ? 'OpenRouter API key'
                  : 'OpenAI API key',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Model',
              helperText: _provider == 'openrouter'
                  ? 'e.g. google/gemini-2.0-flash-lite (cheap)'
                  : 'e.g. gpt-4o-mini',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('Test connection'),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                    ok
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: ok ? MtTheme.accent : MtTheme.danger,
                    size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_testResult!,
                        style: TextStyle(
                            color: ok ? MtTheme.accent : MtTheme.danger))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
