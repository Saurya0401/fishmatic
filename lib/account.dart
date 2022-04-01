import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import './backend/data_models.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({Key? key, required this.fbAuth}) : super(key: key);

  final FirebaseAuth fbAuth;

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  TextEditingController? _emailCtrl, _passCtrl, _confCtrl;
  String? _statusText;
  String? _confError;
  bool _signingUp = false;
  bool _validEmail = true;
  bool _validPass = true;
  bool _validConf = true;
  bool _signUpSuccess = false;

  Future<void> _signUp() async {
    setState(() {
      _statusText = null;
      _signingUp = true;
      _validEmail = true;
      _validPass = true;
      _validConf = true;
      if (_emailCtrl!.text.isEmpty) {
        _validEmail = false;
        _signingUp = false;
      }
      if (_passCtrl!.text.isEmpty) {
        _validPass = false;
        _signingUp = false;
      }
      if (_confCtrl!.text.isEmpty || _confCtrl!.text != _passCtrl!.text) {
        _validConf = false;
        _confError = _confCtrl!.text.isEmpty
            ? 'Please confirm password'
            : 'Passwords do not match';
        _signingUp = false;
      }
    });
    if (_validEmail && _validPass && _validConf) {
      try {
        await widget.fbAuth.createUserWithEmailAndPassword(
          email: _emailCtrl!.text,
          password: _passCtrl!.text,
        );
        showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => SimpleDialog(
                  title: Text('Sign Up Success'),
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text('Account successfully created!'),
                        ),
                        SizedBox(
                          height: 80.0,
                          child: Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ElevatedButton(
                              onPressed: () => Navigator.popUntil(
                                  context, ModalRoute.withName('/login')),
                              child: Text('Log In')),
                        ),
                      ],
                    ),
                  ],
                ));
      } on FirebaseAuthException catch (error) {
        if (error.code == 'weak-password') {
          _showError('Password is too weak');
        } else if (error.code == 'email-already-in-use') {
          _showError('An account already exists under this email');
        }
      }
    }
  }

  void _showError(String errorMessage) {
    setState(() {
      _signingUp = false;
      _signUpSuccess = false;
      _statusText = errorMessage;
    });
  }

  @override
  void initState() {
    _emailCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    _confCtrl = TextEditingController();
    super.initState();
  }

  @override
  void dispose() {
    _emailCtrl?.dispose();
    _passCtrl?.dispose();
    _confCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Fishmatic',
          style: TextStyle(
            fontSize: 25.0,
            fontStyle: FontStyle.italic,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: Column(
              children: <Widget>[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 32.0, horizontal: 16.0),
                    child: Text(
                      'Sign up for a new account',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                SizedBox(
                  width: 250.0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: 5.0),
                        child: Text(
                          'Email',
                          style: TextStyle(fontSize: 16.0),
                        ),
                      ),
                      TextField(
                        key: Key('signup_email_field'),
                        enabled: !_signingUp,
                        controller: _emailCtrl!,
                        decoration: InputDecoration(
                            isDense: true,
                            errorText:
                                _validEmail ? null : 'Please enter email'),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 20.0),
                        child: Text(
                          'Password',
                          style: TextStyle(fontSize: 16.0),
                        ),
                      ),
                      TextField(
                        key: Key('signup_password_field'),
                        enabled: !_signingUp,
                        controller: _passCtrl!,
                        obscureText: true,
                        decoration: InputDecoration(
                            isDense: true,
                            errorText:
                                _validPass ? null : 'Please enter password'),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 20.0),
                        child: Text(
                          'Confirm Password',
                          style: TextStyle(fontSize: 16.0),
                        ),
                      ),
                      TextField(
                        key: Key('signup_confirm_field'),
                        enabled: !_signingUp,
                        controller: _confCtrl!,
                        obscureText: true,
                        decoration: InputDecoration(
                            isDense: true,
                            errorText: _validConf ? null : _confError),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Center(
                          child: SizedBox(
                            width: 88,
                            child: ElevatedButton(
                              onPressed: _signingUp
                                  ? null
                                  : () async => await _signUp(),
                              child: _signingUp
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(),
                                    )
                                  : Text('Sign Up'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_statusText != null)
                  Text(
                    _statusText!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _signUpSuccess ? Colors.green : Colors.red,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key, this.testAuth}) : super(key: key);

  static const route = RouteNames.login;
  final FirebaseAuth? testAuth;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  TextEditingController? _emailCtrl, _passCtrl;
  FirebaseAuth? _fbAuth;
  String? _statusText;
  bool _loggingIn = false;
  bool _validEmail = true;
  bool _validPass = true;
  bool _loginSuccess = false;

  Future<void> _login() async {
    setState(() {
      _statusText = null;
      _loggingIn = true;
      _validEmail = true;
      _validPass = true;
      if (_emailCtrl!.text.isEmpty) {
        _validEmail = false;
        _loggingIn = false;
      }
      if (_passCtrl!.text.isEmpty) {
        _validPass = false;
        _loggingIn = false;
      }
    });
    if (_validEmail && _validPass) {
      try {
        await _fbAuth!.signInWithEmailAndPassword(
          email: _emailCtrl!.text,
          password: _passCtrl!.text,
        );
        if (widget.testAuth != null)
          Navigator.pop(context);
        else
          Navigator.pushReplacementNamed(context, RouteNames.home);
      } on FirebaseAuthException catch (error) {
        if (error.code == 'user-not-found') {
          _showError('User not found, please sign-up');
        } else if (error.code == 'wrong-password') {
          _showError('Incorrect password');
        }
      }
    }
  }

  void _showError(String errorMessage) {
    setState(() {
      _loggingIn = false;
      _loginSuccess = false;
      _statusText = errorMessage;
    });
  }

  @override
  void initState() {
    _fbAuth = widget.testAuth ?? FirebaseAuth.instance;
    _emailCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    super.initState();
  }

  @override
  void dispose() {
    _emailCtrl?.dispose();
    _passCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Fishmatic',
          style: TextStyle(
            fontSize: 25.0,
            fontStyle: FontStyle.italic,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: Column(
              children: <Widget>[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 32.0, horizontal: 16.0),
                    child: Text(
                      'Sign in to your account',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                SizedBox(
                  width: 250.0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: 5.0),
                        child: Text(
                          'Email',
                          style: TextStyle(fontSize: 16.0),
                        ),
                      ),
                      TextField(
                        key: Key('login_email_field'),
                        enabled: !_loggingIn,
                        controller: _emailCtrl!,
                        decoration: InputDecoration(
                            isDense: true,
                            errorText:
                                _validEmail ? null : 'Please enter email'),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 20.0),
                        child: Text(
                          'Password',
                          style: TextStyle(fontSize: 16.0),
                        ),
                      ),
                      TextField(
                        key: Key('login_password_field'),
                        enabled: !_loggingIn,
                        controller: _passCtrl!,
                        obscureText: true,
                        decoration: InputDecoration(
                            isDense: true,
                            errorText:
                                _validPass ? null : 'Please enter password'),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: SizedBox(
                              width: 88,
                              child: ElevatedButton(
                                onPressed: _loggingIn
                                    ? null
                                    : () async => await _login(),
                                child: _loggingIn
                                    ? SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator())
                                    : Text(' Login '),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                0.0, 24.0, 24.0, 24.0),
                            child: SizedBox(
                              width: 88,
                              child: ElevatedButton(
                                onPressed: _loggingIn
                                    ? null
                                    : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => SignUpPage(
                                              fbAuth: _fbAuth!,
                                            ),
                                          ),
                                        ),
                                child: Text('Sign In'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_statusText != null)
                  Text(
                    _statusText!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _loginSuccess ? Colors.green : Colors.red,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
