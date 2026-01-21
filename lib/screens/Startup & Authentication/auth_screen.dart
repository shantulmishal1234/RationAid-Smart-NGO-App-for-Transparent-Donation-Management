import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ration_aid/screens/dashboard_router.dart';
import 'package:ration_aid/services/auth_service.dart';
import 'package:ration_aid/services/audit_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();

  // Separate form keys
  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();

  // Login form controllers
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Signup form controllers
  final _signupEmailController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  late TabController _tabController;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  int _passwordStrength = 0;

  final _passwordRegExp = RegExp(r'^(?=.*[A-Z])(?=.*[!@#$%^&*]).{6,}$');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signupEmailController.dispose();
    _signupPasswordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _checkPasswordStrength(String password) {
    int strength = 0;
    if (password.length >= 6) strength++;
    if (password.length >= 10) strength++;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
    if (RegExp(r'[0-9]').hasMatch(password)) strength++;
    if (RegExp(r'[!@#$%^&*]').hasMatch(password)) strength++;

    setState(() => _passwordStrength = strength > 4 ? 4 : strength);
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _routeAfterLogin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = doc.data() ?? {};
    final roles = List<String>.from(data['roles'] ?? []);

    await doc.reference.update({'lastLoginAt': FieldValue.serverTimestamp()});

    await AuditService.logSystemAction(
      action: 'User login',
      details: '${user.email} logged in with roles: ${roles.join(", ")}',
    );

    const target = DashboardRouter();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => target),
    );
  }

  Future<void> _handleSignup() async {
    if (!_signupFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await _authService.signUpWithEmail(
      email: _signupEmailController.text.trim(),
      password: _signupPasswordController.text,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      role: 'donor',
    );

    setState(() => _isLoading = false);

    if (result['success']) {
      await AuditService.logSystemAction(
        action: 'New user registration',
        details: '${_signupEmailController.text.trim()} registered as donor',
      );

      _signupEmailController.clear();
      _signupPasswordController.clear();
      _confirmPasswordController.clear();
      _nameController.clear();
      _phoneController.clear();
      setState(() {
        _passwordStrength = 0;
      });

      _showMessage(
        'Account created! Please check your email to verify before logging in.',
        isError: false,
      );

      _tabController.animateTo(0);
    } else {
      _showMessage(result['message']);
    }
  }

  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await _authService.signInWithEmail(
      email: _loginEmailController.text.trim(),
      password: _loginPasswordController.text,
    );

    setState(() => _isLoading = false);

    if (result['success']) {
      final isVerified = result['isVerified'] ?? true;

      if (!mounted) return;

      if (!isVerified) {
        _showMessage(
          'Please verify your email before logging in. Check your inbox.',
        );
        _showResendVerificationDialog();
        return;
      }

      _loginEmailController.clear();
      _loginPasswordController.clear();

      await _routeAfterLogin();
    } else {
      _showMessage(result['message']);
    }
  }

  Future<void> _handlePasswordReset() async {
    if (_loginEmailController.text.trim().isEmpty) {
      _showMessage('Please enter your email first');
      return;
    }

    final result = await _authService.resetPassword(
      _loginEmailController.text.trim(),
    );

    if (result['success']) {
      await AuditService.logSystemAction(
        action: 'Password reset requested',
        details:
            'Password reset email sent to ${_loginEmailController.text.trim()}',
      );
    }

    _showMessage(result['message'], isError: !result['success']);
  }

  void _showResendVerificationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Email not verified'),
        content: const Text(
          'Please check your inbox and verify your email. '
          'Would you like us to resend the verification link?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await _authService.resendVerificationEmail();
              _showMessage(result['message'], isError: !result['success']);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Resend', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async {
        if (_tabController.index != 0) {
          _tabController.animateTo(0);
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [Colors.black, Colors.black]
                  : [const Color(0xFF1E88E5), const Color(0xFF26A69A)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: DefaultTabController(
                length: 2,
                initialIndex: _tabController.index,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(
                                isDark ? 0.3 : 0.08,
                              ),
                              blurRadius: 24,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Image.asset(
                              'assets/images/app_logo.png',
                              height: 70,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                    Icons.volunteer_activism,
                                    size: 70,
                                    color: Theme.of(context).primaryColor,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Welcome to Ration Aid',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Connecting help with need',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Tabs pill
                            Container(
                              height: 46,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: TabBar(
                                controller: _tabController,
                                padding: const EdgeInsets.all(4),
                                indicator: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Theme.of(context).colorScheme.primary,
                                      Theme.of(context).colorScheme.secondary,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                labelColor: Colors.white,
                                unselectedLabelColor: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[700],
                                dividerColor: Colors.transparent,
                                splashBorderRadius: BorderRadius.circular(24),
                                tabs: const [
                                  Tab(child: Center(child: Text('Login'))),
                                  Tab(child: Center(child: Text('Signup'))),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Content
                            SizedBox(
                              height: 600,
                              child: TabBarView(
                                controller: _tabController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  _buildLoginForm(),
                                  _buildSignupForm(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // LOGIN FORM
  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            controller: _loginEmailController,
            label: 'Email',
            icon: Icons.email,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value!.isEmpty || !value.contains('@')) {
                return 'Enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _loginPasswordController,
            label: 'Password',
            icon: Icons.lock,
            isPassword: true,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey[600],
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            validator: (value) {
              if (value!.isEmpty) return 'Password required';
              return null;
            },
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _handlePasswordReset,
              child: Text(
                'Forgot password?',
                style: TextStyle(color: Theme.of(context).primaryColor),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _buildPrimaryButton(text: 'Login', onPressed: _handleLogin),
        ],
      ),
    );
  }

  // SIGNUP FORM
  Widget _buildSignupForm() {
    return Form(
      key: _signupFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            controller: _nameController,
            label: 'Full name',
            icon: Icons.person,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
            ],
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Name required';
              if (value.trim().length < 2) {
                return 'Name must be at least 2 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _phoneController,
            label: 'Phone number',
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Phone number required';
              }
              // Remove spaces and dashes for validation
              final cleanPhone = value.replaceAll(RegExp(r'[\s-]'), '');
              // Pakistan phone: 03XX-XXXXXXX (11 digits starting with 03)
              if (!RegExp(r'^03[0-9]{9}$').hasMatch(cleanPhone)) {
                return 'Enter valid Pakistani phone (e.g., 0300-1234567)';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _signupEmailController,
            label: 'Email',
            icon: Icons.email,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value!.isEmpty || !value.contains('@')) {
                return 'Enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _signupPasswordController,
            label: 'Password',
            icon: Icons.lock,
            isPassword: true,
            obscureText: _obscurePassword,
            onChanged: _checkPasswordStrength,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey[600],
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            validator: (value) {
              if (value!.isEmpty) return 'Password required';
              if (!_passwordRegExp.hasMatch(value)) {
                return 'Password: 6+ chars, uppercase & special char';
              }
              return null;
            },
          ),
          if (_signupPasswordController.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildPasswordMeter(),
          ],
          const SizedBox(height: 16),
          _buildTextField(
            controller: _confirmPasswordController,
            label: 'Confirm Password',
            icon: Icons.lock_outline,
            isPassword: true,
            obscureText: _obscureConfirmPassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
                color: Colors.grey[600],
              ),
              onPressed: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
            ),
            validator: (value) {
              if (value!.isEmpty) return 'Please confirm password';
              if (value != _signupPasswordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildDonorInfoCard(),
          const SizedBox(height: 22),
          _buildPrimaryButton(text: 'Sign up', onPressed: _handleSignup),
        ],
      ),
    );
  }

  Widget _buildPasswordMeter() {
    Color barColor;
    String label;
    if (_passwordStrength < 2) {
      barColor = Colors.red;
      label = 'Weak';
    } else if (_passwordStrength < 3) {
      barColor = Colors.orange;
      label = 'Fair';
    } else if (_passwordStrength < 4) {
      barColor = Colors.lightGreen;
      label = 'Good';
    } else {
      barColor = Colors.green;
      label = 'Strong';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _passwordStrength / 4,
                backgroundColor: Colors.grey[300],
                color: barColor,
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: barColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDonorInfoCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.green[900]!.withOpacity(0.3) : Colors.green[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.green[800]! : Colors.green[200]!,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            Icons.volunteer_activism,
            color: isDark ? Colors.green[300] : Colors.green[700],
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Signing up as a donor',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.green[100] : Colors.green[900],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Support families in need with regular contributions.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.green[200] : Colors.green[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).colorScheme.secondary,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withOpacity(0.32),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      text,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    void Function(String)? onChanged,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        onChanged: onChanged,
        inputFormatters: inputFormatters,
        style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          prefixIcon: Icon(
            icon,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
