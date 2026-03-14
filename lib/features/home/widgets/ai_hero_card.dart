import 'dart:async';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/utils/toast_service.dart'; 
import '../../../../core/widgets/ridel_sheet.dart'; 
import 'package:ridel/features/tour/screens/chat_screen.dart';
import 'package:ridel/core/widgets/notification_sheet.dart'; 
import 'package:ridel/core/services/universal_mic_button.dart';
import 'package:ridel/core/services/notification_service.dart';

class AiHeroCard extends StatefulWidget {
  final Function(String) onSearch; 
  const AiHeroCard({super.key, required this.onSearch});

  @override
  State<AiHeroCard> createState() => _AiHeroCardState();
}

class _AiHeroCardState extends State<AiHeroCard> {
  bool _isSearchActive = false;
  bool _isChatActive = false; 
  bool _isTyping = false;
  bool _isAiThinking = false;
  
  final TextEditingController _aiInputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  
  final Color neonCyan = const Color(0xFF00E5FF);

  // 📝 SMART TYPEWRITER ENGINE STATES
  String _typewriterText = "";
  int _twTextIndex = 0;
  int _twCharIndex = 0;
  bool _twIsDeleting = false;
  Timer? _twTimer;

  List<String> _twStrings = [];
  List<Map<String, String>> _chatHistory = [];

  @override
  void initState() {
    super.initState();
    _initDynamicPrompts();
    _startTypewriter();

    _aiInputController.addListener(() {
      if (_aiInputController.text.isNotEmpty && !_isTyping) {
        setState(() => _isTyping = true);
      } else if (_aiInputController.text.isEmpty && _isTyping) {
        setState(() => _isTyping = false);
      }
    });
  }

  void _initDynamicPrompts() {
    final hour = DateTime.now().hour;
    String greeting = "Good evening";
    if (hour < 12) {
      greeting = "Good morning";
    } else if (hour < 17) {
      greeting = "Good afternoon";
    }

    String firstName = "Radhe"; 
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && user.userMetadata != null && user.userMetadata!['full_name'] != null) {
        String fullName = user.userMetadata!['full_name'];
        if (fullName.isNotEmpty) {
          // Sirf first name nikalne ke liye
          firstName = fullName.split(' ')[0]; 
        }
      }
    } catch (e) {}

    // 🔥 EXTRA SAFETY: Agar first name 12 characters se bada hai, toh use wahin truncate kar do
    if (firstName.length > 12) {
      firstName = '${firstName.substring(0, 10)}...';
    }

    _twStrings = [
      "Welcome to Ridel!",
      "$greeting, $firstName! 👋",
      "I'm your personal AI assistant.",
      "Would you like to explore India?",
      "Tell me your travel mood...",
      "Looking for a peaceful temple?",
      "Planning a weekend getaway?",
    ];
  }

  void _startTypewriter() {
    _twTimer = Timer.periodic(Duration(milliseconds: _twIsDeleting ? 15 : 40), (timer) {
      if (!mounted) return;
      
      String currentString = _twStrings[_twTextIndex];
      int totalChars = currentString.characters.length;

      if (!_twIsDeleting) {
        if (_twCharIndex < totalChars) {
          setState(() {
            _twCharIndex++;
            _typewriterText = currentString.characters.take(_twCharIndex).toString();
          });
        } else {
          timer.cancel();
          int pauseTime = (_twTextIndex == 0 || _twTextIndex == 1) ? 3500 : 2000;
          Future.delayed(Duration(milliseconds: pauseTime), () {
            if (mounted) {
              _twIsDeleting = true;
              _startTypewriter();
            }
          });
        }
      } else {
        if (_twCharIndex > 0) {
          setState(() {
            _twCharIndex--;
            _typewriterText = currentString.characters.take(_twCharIndex).toString();
          });
        } else {
          _twIsDeleting = false;
          _twTextIndex = (_twTextIndex + 1) % _twStrings.length;
          timer.cancel();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) _startTypewriter();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _twTimer?.cancel();
    _aiInputController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _activateChat() {
    AppHaptics.mediumImpact();
    setState(() => _isChatActive = true);
    _focusNode.requestFocus();
  }

void _openFullScreenChat() {
  AppHaptics.heavyImpact();
  Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0); // Niche se upar aayega
        const end = Offset.zero;
        const curve = Curves.fastOutSlowIn;
        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    )
  );
}

  void _deactivateChat() {
    AppHaptics.lightImpact();
    FocusScope.of(context).unfocus();
    setState(() {
      _isChatActive = false;
      _chatHistory.clear();
      _isAiThinking = false;
      _aiInputController.clear();
    });
  }

  void _sendToAI() async {
    final text = _aiInputController.text.trim();
    if (text.isEmpty) return;

    AppHaptics.heavyImpact();
    FocusScope.of(context).unfocus(); 

    setState(() {
      _chatHistory.add({'role': 'user', 'text': text});
      _isAiThinking = true;
      _aiInputController.clear();
    });

    widget.onSearch(text);
    await Future.delayed(const Duration(milliseconds: 1500));

    if (mounted) {
      AppHaptics.lightImpact();
      setState(() {
        _chatHistory.add({'role': 'ai', 'text': "I've curated some perfect spots for you. Check the list below!"});
        _isAiThinking = false;
      });
    }
  }

  Widget _buildTypewriterText(Color textColor) {
    bool isPrimaryMessage = (_twTextIndex == 0 || _twTextIndex == 1);
    double currentFontSize = isPrimaryMessage ? 25.0 : 19.0;
    
    // Constant Orb size
    double dotSize = 20.0; 
    double dotBottomMargin = isPrimaryMessage ? 5.0 : 3.0; 

    return RichText(
      maxLines: 1, 
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: _typewriterText,
            style: TextStyle(
              color: textColor, 
              fontSize: currentFontSize, 
              fontWeight: isPrimaryMessage ? FontWeight.bold : FontWeight.w600, 
              height: 1.3
            ),
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: EdgeInsets.only(left: 8, bottom: dotBottomMargin), 
              width: dotSize,  
              height: dotSize, 
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 5, offset: const Offset(0, 2))
                ]
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🚀 RECENT SEARCHES COMPONENT
  Widget _buildRecentSearches(bool isDark, Color hintColor, Color textColor) {
    return Container(
      key: const ValueKey('recent_searches'),
      height: 128, 
      margin: const EdgeInsets.only(top: 4), 
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, color: hintColor, size: 16),
              const SizedBox(width: 8),
              Text("Recent Searches", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Icon(Icons.keyboard_arrow_up_rounded, color: hintColor, size: 18),
            ],
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10), 
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: neonCyan.withOpacity(0.15),
                    boxShadow: [BoxShadow(color: neonCyan.withOpacity(0.2), blurRadius: 15, spreadRadius: 1)],
                  ),
                  child: Icon(Icons.rocket_launch_rounded, color: neonCyan, size: 20), 
                ),
                const SizedBox(height: 8),
                Text("Your search history is empty.", style: TextStyle(color: hintColor, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 💬 DEFAULT MIDDLE AND BOTTOM COMPONENT
  Widget _buildDefaultMiddleAndBottom(bool isDark, Color hintColor, Color textColor) {
    return Container(
      key: const ValueKey('default_ui'),
      height: 128, 
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 60, 
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildTypewriterText(textColor), 
            ),
          ),
          
          const SizedBox(height: 8), 

          Container(
            height: 50, 
            padding: const EdgeInsets.only(left: 6, right: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.black12 : Colors.white60, 
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _activateChat,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        Icon(Icons.mic_none_rounded, color: hintColor, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text("Tap to start planning...", style: TextStyle(color: hintColor, fontSize: 14, fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),
                ),
                
                GestureDetector(
                  onTap: _openFullScreenChat,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white : Colors.black,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [BoxShadow(color: neonCyan.withOpacity(isDark ? 0.3 : 0.15), blurRadius: 12, offset: const Offset(0, 2))],
                    ),
                    child: Row(
                      children: [
                        Text("Chat", style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.w800, fontSize: 13)), 
                        const SizedBox(width: 6), 
                        Icon(Icons.auto_awesome, color: isDark ? Colors.black : Colors.white, size: 14)
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final List<Color> bgGradient = isDark 
        ? [const Color(0xFF001515), const Color(0xFF002B2B)]
        : [Colors.white, const Color(0xFFE0F7FA)];
        
    final Color textColor = isDark ? Colors.white : Colors.black;
    final Color hintColor = isDark ? Colors.white54 : Colors.black54; 
    final Color badgeBg = isDark ? const Color(0xFF003838) : Colors.cyan.withOpacity(0.1);
    final Color btnBg = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);
    final Color iconColor = isDark ? Colors.white : Colors.black87; 
    final Color borderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05);

    return Container(
      width: double.infinity,
      height: 218, 
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(35), 
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: bgGradient,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(isDark ? 0.4 : 0.08), blurRadius: 30, offset: const Offset(0, 15))
        ],
        border: Border.all(color: borderColor),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60, left: -60,
            child: Container(
              width: 180, height: 180,
              decoration: BoxDecoration(shape: BoxShape.circle, color: neonCyan.withOpacity(isDark ? 0.1 : 0.05)),
              child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60), child: Container(color: Colors.transparent)),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20.0), 
            child: AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: _isChatActive ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              
              // ==========================================
              // INACTIVE & SEARCH STATES
              // ==========================================
              firstChild: SizedBox(
                height: 178, 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return SizedBox(
                          height: 50, 
                          width: constraints.maxWidth,
                          child: Stack(
                            alignment: Alignment.centerRight,
                            children: [
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _isSearchActive ? 0.0 : 1.0,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: neonCyan.withOpacity(0.3))),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.auto_awesome, color: neonCyan, size: 14), 
                                        const SizedBox(width: 6), 
                                        Text("AI TRIP PLANNER", style: TextStyle(color: neonCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5))
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              
                              // 🔥 FIX: The Glassy Search Bar with OverflowBox
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutBack,
                                width: _isSearchActive ? constraints.maxWidth : 44, 
                                height: _isSearchActive ? 50 : 44, 
                                clipBehavior: Clip.hardEdge, 
                                decoration: BoxDecoration(
                                  color: _isSearchActive ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05)) : btnBg, 
                                  borderRadius: BorderRadius.circular(100), 
                                  border: _isSearchActive ? Border.all(color: isDark ? Colors.white24 : Colors.black12) : null
                                ),
                                child: _isSearchActive 
                                  ? OverflowBox(
                                      // Ye magic shield hai jo error aane se rokega
                                      maxWidth: constraints.maxWidth,
                                      minWidth: constraints.maxWidth,
                                      maxHeight: 50,
                                      minHeight: 50,
                                      alignment: Alignment.centerLeft,
                                      child: Row(
                                        children: [
                                          Padding(padding: const EdgeInsets.only(left: 16.0), child: Icon(Icons.search, color: iconColor, size: 18)),
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 10.0),
                                              child: TextField(
                                                controller: _searchController, 
                                                focusNode: _searchFocusNode,
                                                style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500), 
                                                cursorColor: neonCyan, 
                                                decoration: InputDecoration(
                                                  hintText: "Search places...", 
                                                  hintStyle: TextStyle(color: hintColor, fontSize: 14), 
                                                  border: InputBorder.none, 
                                                  isDense: true, 
                                                  contentPadding: EdgeInsets.zero
                                                )
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () { 
                                              AppHaptics.lightImpact(); 
                                              setState(() => _isSearchActive = false); 
                                              _searchController.clear(); 
                                              FocusScope.of(context).unfocus();
                                            },
                                            child: Padding(padding: const EdgeInsets.only(right: 16.0), child: Icon(Icons.close, color: textColor, size: 20)),
                                          ),
                                        ],
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: () { 
                                        AppHaptics.mediumImpact(); 
                                        setState(() => _isSearchActive = true); 
                                        _searchFocusNode.requestFocus();
                                      },
                                      child: Center(child: Icon(Icons.search_rounded, color: iconColor, size: 20)),
                                    ),
                              ),
                            ],
                          ),
                        );
                      }
                    ),

                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                          return Stack(
                            alignment: Alignment.bottomLeft,
                            children: <Widget>[
                              ...previousChildren,
                              if (currentChild != null) currentChild,
                            ],
                          );
                        },
                        child: _isSearchActive 
                            ? _buildRecentSearches(isDark, hintColor, textColor)
                            : _buildDefaultMiddleAndBottom(isDark, hintColor, textColor),
                      ),
                    ),
                  ],
                ),
              ),

              // ==========================================
              // ACTIVE CHAT STATE 
              // ==========================================
              secondChild: SizedBox(
                height: 178,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _chatHistory.isEmpty
                            ? SizedBox(
                                height: 50,
                                child: Align(alignment: Alignment.centerLeft, child: _buildTypewriterText(textColor))
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '"${_chatHistory.lastWhere((m) => m['role'] == 'user')['text']}"',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: hintColor, fontSize: 13, fontStyle: FontStyle.italic),
                                  ),
                                  const SizedBox(height: 6),
                                  if (_isAiThinking)
                                    Row(
                                      children: [
                                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: neonCyan, strokeWidth: 2)),
                                        const SizedBox(width: 8),
                                        Text("Exploring places...", style: TextStyle(color: neonCyan, fontSize: 14, fontWeight: FontWeight.w600)),
                                      ],
                                    )
                                  else
                                    Text(
                                      _chatHistory.lastWhere((m) => m['role'] == 'ai', orElse: () => {'text': ''})['text']!,
                                      maxLines: 2, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
                                    ),
                                ],
                              ),
                        ),
                        GestureDetector(
                          onTap: _deactivateChat,
                          child: Container(
                            margin: const EdgeInsets.only(left: 10),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: btnBg, shape: BoxShape.circle),
                            child: Icon(Icons.close, color: textColor, size: 14),
                          ),
                        )
                      ],
                    ),
                    
                    const Spacer(),

                    Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0D1217) : Colors.grey.shade100, 
                        borderRadius: BorderRadius.circular(100), 
                        border: Border.all(color: isDark ? Colors.white12 : Colors.black12, width: 1),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () { AppHaptics.lightImpact(); },
                            child: Container(
                              color: Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
                              child: Icon(Icons.tune_rounded, color: neonCyan, size: 20),
                            ),
                          ),
                          
                          Expanded(
                            child: TextField(
                              controller: _aiInputController, 
                              focusNode: _focusNode,
                              onSubmitted: (_) => _sendToAI(),
                              style: TextStyle(color: textColor, fontSize: 14), 
                              cursorColor: neonCyan,
                              decoration: InputDecoration(
                                hintText: "Describe your ideal trip...", 
                                hintStyle: TextStyle(color: hintColor, fontSize: 14), 
                                border: InputBorder.none, 
                                isDense: true,
                              ),
                            ),
                          ),
                          
                          if (!_isTyping)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: UniversalMicButton(
                                isDark: isDark, size: 20, activeColor: neonCyan,
                                onTextRecognized: (text) { 
                                  _aiInputController.text = text; 
                                  _sendToAI(); 
                                },
                              ),
                            )
                          else
                            GestureDetector(
                              onTap: _sendToAI,
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: neonCyan, 
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: neonCyan.withOpacity(0.3), blurRadius: 6)]
                                ),
                                child: const Icon(Icons.send_rounded, color: Colors.black, size: 16),
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
        ],
      ),
    );
  }
}