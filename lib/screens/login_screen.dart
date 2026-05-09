import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'otp_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  bool _isValid = false;
  bool _isLoading = false;

  void _checkValid() {
    final text = _phoneController.text.trim();
    setState(() {
      _isValid = RegExp(r'^\d{10}$').hasMatch(text);
    });
  }

  Future<void> _sendOtp() async {
    setState(() => _isLoading = true);
    try {
      await ApiService.requestOtp(_phoneController.text.trim());
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OTPScreen(phoneNumber: _phoneController.text.trim()),
        ),
      );
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

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_checkValid);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_checkValid);
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF090F29), Color(0xFF110934), Color(0xFF070612)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            top: -90,
            left: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color.fromRGBO(128, 0, 128, 0.35), Colors.transparent]),
              ),
            ),
          ),
          Positioned(
            top: 70,
            right: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color.fromRGBO(255, 105, 180, 0.25), Colors.transparent]),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text('FRND', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white12,
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text('Welcome back', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 10),
                  const Text('Get back in the room', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, height: 1.1)),
                  const SizedBox(height: 16),
                  const Text('Login with your phone number and tap into your friend circle instantly.', style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
                  const SizedBox(height: 32),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101835),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.08)),
                      boxShadow: [
                        BoxShadow(color: const Color.fromRGBO(0, 0, 0, 0.24), blurRadius: 28, offset: const Offset(0, 16)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Phone number', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          style: const TextStyle(color: Colors.white, fontSize: 18),
                          decoration: const InputDecoration(
                            hintText: '9876543210',
                            prefixIcon: Icon(Icons.phone, color: Colors.white70),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 22),
                        ElevatedButton(
                          onPressed: _isValid && !_isLoading ? _sendOtp : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isValid ? const Color(0xFFFF5AA2) : Colors.white12,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Send OTP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isCompact = constraints.maxWidth < 380;
                              return Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: isCompact ? 8 : 12,
                                runSpacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () {
                                            Navigator.push(context, MaterialPageRoute(builder: (context) => const SignupScreen()));
                                          },
                                    child: const Text('Create a FRND account', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                  ),
                                  OutlinedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () {
                                            Navigator.push(context, MaterialPageRoute(builder: (context) => const SignupScreen(isPartner: true)));
                                          },
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Color(0xFFFF5AA2)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                    child: const Text('Become a partner', style: TextStyle(color: Color(0xFFFF5AA2), fontSize: 14, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: const [
                      Expanded(child: Divider(color: Colors.white12)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text('or continue with', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ),
                      Expanded(child: Divider(color: Colors.white12)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: const [
                      Expanded(child: _SocialButton(label: 'Google', icon: Icons.g_mobiledata)),
                      SizedBox(width: 14),
                      Expanded(child: _SocialButton(label: 'Apple', icon: Icons.apple)),
                    ],
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

class _SocialButton extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SocialButton({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {},
      icon: Icon(icon, color: Colors.white70),
      label: Text(label, style: const TextStyle(color: Colors.white70)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.white12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}
