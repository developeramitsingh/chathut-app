import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SignupScreen extends StatefulWidget {
  final bool isPartner;

  const SignupScreen({super.key, this.isPartner = false});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  String _selectedGender = 'female';
  bool _isPartner = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isPartner = widget.isPartner;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty || _phoneController.text.trim().length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid name and 10-digit phone number')));
      return;
    }

    if (_isPartner && _selectedGender != 'female') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Partner registration is available for female users only.')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ApiService.signup(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        gender: _selectedGender,
        role: _isPartner ? 'partner' : 'user',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signup successful. Please login.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.deepPurple.shade300),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: const Color(0xFFFF5AA2)),
      filled: true,
      fillColor: const Color(0xFF121835),
      counterText: '',
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF090C25), Color(0xFF130D3F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -50,
            right: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: const BoxDecoration(
                color: Color.fromRGBO(255, 182, 193, 0.18),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: 120,
            left: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(128, 0, 128, 0.24),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isPartner ? 'Become a partner with FRND' : 'Create your FRND profile',
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isPartner
                        ? 'Female creators can register to earn money, go live, and connect with users.'
                        : 'Sign up to join live rooms, chat with friends, and send gifts.',
                    style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
                  ),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121738),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.08)),
                      boxShadow: [
                        BoxShadow(color: const Color.fromRGBO(0, 0, 0, 0.26), blurRadius: 26, offset: const Offset(0, 16)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _nameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('Full Name', Icons.person),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('Phone Number', Icons.phone_android),
                        ),
                        const SizedBox(height: 18),
                        const Text('Gender', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _GenderOption(
                                label: 'Female',
                                value: 'female',
                                selectedValue: _selectedGender,
                                disabled: false,
                                onChanged: (value) => setState(() => _selectedGender = value),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _GenderOption(
                                label: 'Male',
                                value: 'male',
                                selectedValue: _selectedGender,
                                disabled: _isPartner,
                                onChanged: (value) {
                                  if (!_isPartner) setState(() => _selectedGender = value);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _GenderOption(
                                label: 'Other',
                                value: 'other',
                                selectedValue: _selectedGender,
                                disabled: _isPartner,
                                onChanged: (value) {
                                  if (!_isPartner) setState(() => _selectedGender = value);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('Email (optional)', Icons.mail_outline),
                        ),
                        const SizedBox(height: 18),
                        if (_isPartner)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF151835),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFFF5AA2)),
                            ),
                            child: const Text(
                              'Partner registration is for female creators only.',
                              style: TextStyle(color: Color(0xFFFF5AA2), fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        if (_isPartner) const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                            backgroundColor: const Color(0xFFFF5AA2),
                          ),
                          child: _isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(_isPartner ? 'Register as Partner' : 'Create Account', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('Already have an account? Login', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  final String label;
  final String value;
  final String selectedValue;
  final bool disabled;
  final ValueChanged<String> onChanged;

  const _GenderOption({required this.label, required this.value, required this.selectedValue, required this.onChanged, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    final selected = selectedValue == value;
    return GestureDetector(
      onTap: disabled ? null : () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF8E44AD)
              : disabled
                  ? const Color(0xFF111429)
                  : const Color(0xFF151835),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFFF5AA2) : disabled ? Colors.white24 : Colors.white12,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected
                ? Colors.white
                : disabled
                    ? Colors.white38
                    : Colors.white70,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
