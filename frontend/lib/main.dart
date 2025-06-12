import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'config/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'firebase_options.dart';
import 'screens/transcription_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(PianoTranscriptionApp());
}

class PianoTranscriptionApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Piano Transcription',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        primaryColor: AppTheme.primaryColor,
        scaffoldBackgroundColor: AppTheme.backgroundColor,
      ),
      home: AuthWrapper(),
      routes: {
        '/transcription': (context) => TranscriptionScreen(),
      }
    );
  }
}

class AuthWrapper extends StatelessWidget {
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          if (user == null) {
            return LoginScreen();
          }
          return HomeScreen();
        }

        return Scaffold(
          body: Container(
            color: AppTheme.backgroundColor,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              ),
            ),
          ),
        );
      },
    );
  }
}







// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
//
// import 'audio_recorder.dart';
//
// final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
//
// void main() => runApp(const MyApp());
//
// class MyApp extends StatefulWidget {
//   const MyApp({super.key});
//
//   @override
//   State<MyApp> createState() => _MyAppState();
// }
//
// class _MyAppState extends State<MyApp> {
//   bool showPlayer = false;
//   String? audioPath;
//   List<dynamic> notes = [];
//
//   void navigateToNotesDisplay(List<dynamic> detectedNotes) {
//     setState(() {
//       notes = detectedNotes;
//     });
//
//     navigatorKey.currentState!.push(
//       MaterialPageRoute(
//         builder: (context) => NotesDisplay(notes: notes),
//       ),
//     );
//   }
//
//   @override
//   void initState() {
//     showPlayer = false;
//     super.initState();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       navigatorKey: navigatorKey,
//       theme: ThemeData(
//         primarySwatch: Colors.blue,
//         useMaterial3: true,
//         scaffoldBackgroundColor: Colors.white,
//       ),
//       home: Scaffold(
//         appBar: AppBar(
//           title: const Text('Music Transcription App'),
//           centerTitle: true,
//         ),
//         body: Center(
//           child: showPlayer
//               ? Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 25),
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Text('Audio recorded at: $audioPath'),
//                 const SizedBox(height: 20),
//                 ElevatedButton(
//                   onPressed: () {
//                     setState(() {
//                       showPlayer = false;
//                       audioPath = null;
//                     });
//                   },
//                   child: const Text('Record New Audio'),
//                 ),
//               ],
//             ),
//           )
//               : Recorder(
//             onStop: (path) {
//               if (kDebugMode) print('Recorded file path: $path');
//               setState(() {
//                 audioPath = path;
//                 showPlayer = true;
//               });
//             },
//             onNavigateToNotes: navigateToNotesDisplay,
//           ),
//         ),
//       ),
//     );
//   }
// }