import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';
import 'package:trip_planner_app/features/auth/data/auth_service.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignInMode = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final authService = ref.read(authServiceProvider);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      final response = _isSignInMode
          ? await authService.signInWithPassword(email: email, password: password)
          : await authService.signUp(email: email, password: password);

      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      if (!_isSignInMode && response.session == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('註冊成功。若尚未關閉 email 驗證，請先到信箱完成確認。')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text(_isSignInMode ? '登入成功' : '註冊成功，已完成登入')),
        );
      }
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = '登入失敗，請稍後再試。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF5F9FE), Color(0xFFDDE8F3)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Supabase Auth 已接入',
                              style: TextStyle(
                                color: AppColors.accentStrong,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text('桃園嘉義行', style: theme.textTheme.headlineLarge),
                          const SizedBox(height: 12),
                          Text(
                            _isSignInMode
                                ? '使用 Email / Password 登入 Supabase，登入後會自動進入旅程列表。'
                                : '先建立測試帳號，後續再擴充 Google / Apple 登入。',
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.username, AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'name@example.com',
                            ),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (email.isEmpty) {
                                return '請輸入 Email';
                              }
                              if (!email.contains('@')) {
                                return 'Email 格式不正確';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              hintText: '至少 6 碼',
                            ),
                            validator: (value) {
                              final password = value ?? '';
                              if (password.isEmpty) {
                                return '請輸入 Password';
                              }
                              if (password.length < 6) {
                                return 'Password 至少需要 6 碼';
                              }
                              return null;
                            },
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _errorMessage!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _isSubmitting ? null : _submit,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: AppColors.accent,
                            ),
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(_isSignInMode ? Icons.login_rounded : Icons.person_add_alt_1_rounded),
                            label: Text(_isSignInMode ? '登入' : '建立帳號'),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () {
                                    setState(() {
                                      _isSignInMode = !_isSignInMode;
                                      _errorMessage = null;
                                    });
                                  },
                            child: Text(
                              _isSignInMode ? '還沒有帳號？建立測試帳號' : '已經有帳號？返回登入',
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
        ),
      ),
    );
  }
}
