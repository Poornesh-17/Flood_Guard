
import 'dart:async';
import 'package:flutter/material.dart';
import '../app.dart';

class SplashScreen extends StatefulWidget {
const SplashScreen({super.key});

@override
State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
with TickerProviderStateMixin {

late AnimationController _controller;
late AnimationController _loaderController;

late Animation<double> _logoFade;
late Animation<double> _textFade;
late Animation<double> _taglineFade;
late Animation<double> _loaderFade;

late Animation<Offset> _logoSlide;
late Animation<Offset> _textSlide;
late Animation<Offset> _taglineSlide;
late Animation<Offset> _loaderSlide;

Timer? _navigationTimer;

static const Color background = Color(0xFF000000);
static const Color red = Color(0xFFFF1028);
static const Color gray = Color(0xFF292929);

@override
void initState() {
super.initState();

// Main animation controller
_controller = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 2200),
);

// Logo animation
_logoFade = CurvedAnimation(
parent: _controller,
curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
);

_logoSlide = Tween<Offset>(
begin: const Offset(0, 0.8),
end: Offset.zero,
).animate(
CurvedAnimation(
parent: _controller,
curve: const Interval(0.0, 0.45,
curve: Curves.easeOutCubic),
),
);

// App name animation
_textFade = CurvedAnimation(
parent: _controller,
curve: const Interval(0.20, 0.60, curve: Curves.easeIn),
);

_textSlide = Tween<Offset>(
begin: const Offset(0, 0.7),
end: Offset.zero,
).animate(
CurvedAnimation(
parent: _controller,
curve: const Interval(0.20, 0.60,
curve: Curves.easeOutCubic),
),
);

// Tagline animation
_taglineFade = CurvedAnimation(
parent: _controller,
curve: const Interval(0.40, 0.75, curve: Curves.easeIn),
);

_taglineSlide = Tween<Offset>(
begin: const Offset(0, 0.6),
end: Offset.zero,
).animate(
CurvedAnimation(
parent: _controller,
curve: const Interval(0.40, 0.75,
curve: Curves.easeOutCubic),
),
);

// Loading animation entrance
_loaderFade = CurvedAnimation(
parent: _controller,
curve: const Interval(0.60, 1.0, curve: Curves.easeIn),
);

_loaderSlide = Tween<Offset>(
begin: const Offset(0, 0.5),
end: Offset.zero,
).animate(
CurvedAnimation(
parent: _controller,
curve: const Interval(0.60, 1.0,
curve: Curves.easeOutCubic),
),
);

// Continuous loading dots animation
_loaderController = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 1000),
)..repeat();

_controller.forward();

// Navigate to AuthGate after 5 seconds
_navigationTimer = Timer(
const Duration(seconds: 5),
() {
if (!mounted) return;

Navigator.of(context).pushReplacement(
MaterialPageRoute(
builder: (_) => const AuthGate(),
),
);
},
);
}

@override
void dispose() {
_navigationTimer?.cancel();
_controller.dispose();
_loaderController.dispose();
super.dispose();
}

Widget animatedItem({
required Animation<double> fade,
required Animation<Offset> slide,
required Widget child,
}) {
return FadeTransition(
opacity: fade,
child: SlideTransition(
position: slide,
child: child,
),
);
}

// Circular loading dots
Widget buildLoadingDots() {
return AnimatedBuilder(
animation: _loaderController,
builder: (context, child) {
final activeIndex =
(_loaderController.value * 4).floor() % 4;

return Row(
mainAxisAlignment: MainAxisAlignment.center,
children: List.generate(4, (index) {
final isActive = index == activeIndex;

return AnimatedContainer(
duration: const Duration(milliseconds: 200),
margin: const EdgeInsets.symmetric(horizontal: 6),
width: isActive ? 12 : 8,
height: isActive ? 12 : 8,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: isActive ? red : gray,
boxShadow: isActive
? [
BoxShadow(
color: red.withOpacity(0.6),
blurRadius: 10,
spreadRadius: 2,
),
]
    : [],
),
);
}),
);
},
);
}

@override
Widget build(BuildContext context) {
final screenHeight = MediaQuery.of(context).size.height;

return Scaffold(
backgroundColor: background,
body: SafeArea(
child: SizedBox(
width: double.infinity,
height: double.infinity,
child: Column(
  children: [

    const Spacer(flex: 3),

    // CENTRED FLOODGUARD LOGO
    animatedItem(
      fade: _logoFade,
      slide: _logoSlide,
      child: Image.asset(
        'assets/images/logowhite.png',
        width: 175,
        height: screenHeight * 0.25,
        fit: BoxFit.contain,
      ),
    ),

    const SizedBox(height: 28),

    // FLOODGUARD NAME
    animatedItem(
      fade: _textFade,
      slide: _textSlide,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Flood',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 53,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2,
                ),
              ),
              Text(
                'Guard',
                style: TextStyle(
                  color: red,
                  fontSize: 53,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2,
                ),
              ),
            ],
          ),
        ),
      ),
    ),

    const SizedBox(height: 18),

    // TAGLINE
    animatedItem(
      fade: _taglineFade,
      slide: _taglineSlide,
      child: const Text(
        'STAY ALERT  STAY SAFE',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFFD0D0D0),
          fontSize: 13,
          letterSpacing: 4,
        ),
      ),
    ),

    const Spacer(flex: 2),

    // FOUR CIRCULAR LOADING DOTS
    animatedItem(
      fade: _loaderFade,
      slide: _loaderSlide,
      child: buildLoadingDots(),
    ),

    const Spacer(flex: 3),
  ],
),
),
),
);
}
}
