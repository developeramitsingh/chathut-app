import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'partner_home_screen.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class OTPScreen extends StatefulWidget {
  final String phoneNumber;
  const OTPScreen({super.key, required this.phoneNumber});

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final _otpController = TextEditingController();
  bool _isCorrect = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _validateOtp(String value) {
    setState(() {
      _isCorrect = value.trim().length == 4;
    });
  }

  Future<void> _verify() async {
    setState(() => _isLoading = true);
    try {
      await ApiService.login(phone: widget.phoneNumber, otp: _otpController.text.trim());
      if (ApiService.token != null) {
        SocketService.instance.connect(ApiService.token!);
      }
      if (!mounted) return;
      final role = ApiService.currentUser?['role'] as String? ?? 'user';
      if (role == 'partner') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PartnerHomeScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomeScreen()));
      }
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF090F2F), Color(0xFF1A0D4A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 192, 203, 0.14),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -70,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(128, 0, 128, 0.16),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  const Text('Verify OTP', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Text('Enter the 4-digit code sent to +91 ${widget.phoneNumber}', style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5)),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10163B),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white10),
                      boxShadow: [
                        BoxShadow(color: const Color.fromRGBO(0, 0, 0, 0.24), blurRadius: 28, offset: const Offset(0, 16)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Enter your code', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 14),
                          decoration: InputDecoration(
                            hintText: '••••',
                            hintStyle: const TextStyle(color: Colors.white24),
                            counterText: '',
                            filled: true,
                            fillColor: const Color(0xFF1D1C52),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: _validateOtp,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isCorrect && !_isLoading ? _verify : null,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            backgroundColor: _isCorrect ? const Color(0xFFFF5AA2) : Colors.white12,
                          ),
                          child: _isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Verify and Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                        if (!_isCorrect && _otpController.text.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text('Use OTP 1234 for demo login', style: TextStyle(color: Colors.amber, fontSize: 14)),
                        ],
                        const SizedBox(height: 10),
                        const Text('Tip: In demo mode OTP is 1234', style: TextStyle(color: Colors.white38, fontSize: 13)),
                      ],
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
