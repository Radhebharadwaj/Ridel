import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'dart:ui'; // ✅ Required for ImageFilter
import 'dart:math' as math;
import 'package:intl/intl.dart';
import '../../../core/utils/app_haptics.dart'; 

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // Animation Controller for Magic Sparkles
  late AnimationController _magicController;

  // Premium Colors
  final Color neonCyan = const Color(0xFF00E5FF);
  final Color sendGreen = const Color(0xFF00E676); 
  final Color glassBlack = const Color(0xFF151515); 
  final Color bubbleGrey = const Color(0xFF2C2C2E);

  // State
  bool _isTyping = false;
  bool _hasText = false; 
  bool _isAttachmentOpen = false; 
  bool _isHistoryOpen = false;    

  // Messages
  List<Map<String, dynamic>> _messages = [
    {"role": "ai", "type": "text", "message": "Hello! I am your AI Travel Guide. Where are we going today?"},
  ];

  final List<Map<String, dynamic>> _chatHistory = [];

  @override
  void initState() {
    super.initState();
    // ✅ Fast Shimmering Magic Animation
    _magicController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), 
    )..repeat();

    _messageController.addListener(() {
      setState(() {
        _hasText = _messageController.text.trim().isNotEmpty;
      });
    });
  }

  // --- ACTIONS ---

  void _startNewChat() {
    AppHaptics.mediumImpact();
    if (_messages.isNotEmpty) {
      final String dateStr = DateFormat('MMM d, h:mm a').format(DateTime.now());
      final String lastMsg = _messages.last['message'] ?? "Image";
      
      setState(() {
        _chatHistory.insert(0, {
          "date": dateStr,
          "preview": lastMsg.length > 30 ? "${lastMsg.substring(0, 30)}..." : lastMsg,
          "messages": List.from(_messages),
        });
        _messages = [
           {"role": "ai", "type": "text", "message": "Hello! Ready for a new adventure. Where to next?"},
        ];
        _isHistoryOpen = false;
      });
    }
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    AppHaptics.mediumImpact(); 
    final userMsg = _messageController.text.trim();
    
    setState(() {
      _messages.add({"role": "user", "type": "text", "message": userMsg});
      _isTyping = true; 
      _isAttachmentOpen = false; 
      _isHistoryOpen = false;    
    });

    _messageController.clear();
    _scrollToBottom();

    // Simulate AI Response with Magic Animation
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add({
            "role": "ai",
            "type": "text",
            "message": "I have curated a list of hidden gems in mountains. Would you like to explore budget stays?"
          });
        });
        AppHaptics.lightImpact(); 
        _scrollToBottom();
      }
    });
  }

  // Mock Camera Action
  void _handleCameraClick() {
    AppHaptics.mediumImpact();
    setState(() {
      _messages.add({
        "role": "user",
        "type": "image",
        "message": "https://images.unsplash.com/photo-1527631746610-bca00a040d60?q=80&w=1000&auto=format&fit=crop" 
      });
      _isTyping = true;
    });
    _scrollToBottom();
    
    Future.delayed(const Duration(seconds: 2), () {
      if(mounted) {
        setState(() {
          _isTyping = false;
          _messages.add({
            "role": "ai",
            "type": "text",
            "message": "Wow! That looks like a beautiful spot for trekking."
          });
          _scrollToBottom();
        });
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _magicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      resizeToAvoidBottomInset: true, 
      body: Stack(
        children: [
          Column(
            children: [
              // --- HEADER ---
              _buildHeader(context),

              // --- CHAT LIST ---
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _isAttachmentOpen = false;
                      _isHistoryOpen = false;
                    });
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 90), // Bottom padding adjusted for slim bar
                    physics: const BouncingScrollPhysics(),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      // ✅ MAGIC GENERATING ANIMATION
                      if (index == _messages.length && _isTyping) {
                         return _buildMagicGeneratingLoader(); 
                      }
                      
                      final msg = _messages[index];
                      final isUser = msg['role'] == 'user';
                      
                      if (msg['type'] == 'image') {
                        return _buildImageBubble(msg['message'], isUser);
                      }
                      return _buildMessageBubble(msg['message']!, isUser);
                    },
                  ),
                ),
              ),
            ],
          ),

          // --- SMART GLASS INPUT BAR (Bottom Fixed) ---
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildSmartGlassInputBar(),
          ),

          if (_isAttachmentOpen)
            Positioned(bottom: 80, left: 10, child: _buildAttachmentPopup()),

          if (_isHistoryOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _isHistoryOpen = false),
                child: Container(color: Colors.black.withValues(alpha:0.6)), 
              ),
            ),
          
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            right: _isHistoryOpen ? 0 : -300, 
            top: 0, bottom: 0, width: 280, 
            child: _buildHistorySidebar(),
          ),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildHeader(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha:0.1))),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.1), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("AI Travel Guide", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: neonCyan, shape: BoxShape.circle, boxShadow: [BoxShadow(color: neonCyan, blurRadius: 5)])),
                    const SizedBox(width: 6),
                    Text("Online", style: TextStyle(color: neonCyan.withValues(alpha:0.8), fontSize: 12)),
                  ],
                )
              ],
            ),
            const Spacer(),
            IconButton(
              onPressed: _startNewChat,
              icon: const Icon(Icons.add_comment_rounded, color: Colors.white70, size: 22),
            ),
            IconButton(
              onPressed: () {
                 AppHaptics.lightImpact();
                 setState(() { _isHistoryOpen = true; _isAttachmentOpen = false; });
              },
              icon: const Icon(Icons.history, color: Colors.white70, size: 24),
            ),
          ],
        ),
      ),
    );
  }

  // --- MESSAGE BUBBLES ---
  Widget _buildMessageBubble(String text, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) 
            Container(
              margin: const EdgeInsets.only(right: 8, bottom: 4),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF2A2A2A),
                child: Icon(Icons.auto_awesome, color: neonCyan, size: 14),
              ),
            ),
          
          Flexible(
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: text));
                AppHaptics.lightImpact(); // 🔥 Yahan change kiya
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied"), duration: Duration(milliseconds: 800)));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: isUser ? LinearGradient(colors: [neonCyan, const Color(0xFF00B0FF)]) : null,
                  color: isUser ? null : bubbleGrey,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
                    bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
                    bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
                  ),
                ),
                child: Text(text, style: TextStyle(color: isUser ? Colors.black : Colors.white.withValues(alpha:0.95), fontSize: 15, height: 1.4, fontWeight: isUser ? FontWeight.w600 : FontWeight.normal)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageBubble(String imageUrl, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            width: 200, height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha:0.1)),
              image: DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
            ),
          ),
        ],
      ),
    );
  }

  // --- 🌟 REFINED MAGIC ANIMATION (Neon Cyan & White Only) ---
  Widget _buildMagicGeneratingLoader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 40, height: 40,
            child: AnimatedBuilder(
              animation: _magicController,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Main Star (Neon Cyan)
                    Opacity(
                      opacity: 0.5 + 0.5 * math.sin(_magicController.value * 2 * math.pi),
                      child: Icon(Icons.auto_awesome, color: neonCyan, size: 24),
                    ),
                    
                    // Sparkle 1 (Top Left - White)
                    Positioned(
                      top: 4, left: 4,
                      child: Transform.rotate(
                        angle: _magicController.value * math.pi,
                        child: Opacity(
                          opacity: 0.8 * math.cos(_magicController.value * 2 * math.pi).abs(),
                          child: const Icon(Icons.star_rate_rounded, color: Colors.white, size: 10), // ✅ Pure White
                        ),
                      ),
                    ),

                    // Sparkle 2 (Bottom Right - Neon Cyan)
                    Positioned(
                      bottom: 6, right: 4,
                      child: Opacity(
                        opacity: 0.8 * math.sin((_magicController.value + 0.5) * 2 * math.pi).abs(),
                        child: Icon(Icons.star, color: neonCyan.withValues(alpha:0.8), size: 8),
                      ),
                    ),

                    // Sparkle 3 (Top Right - White Glow)
                    Positioned(
                      top: 6, right: 2,
                      child: Opacity(
                        opacity: 0.6 * math.sin(_magicController.value * 4 * math.pi).abs(),
                        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 8), // ✅ Pure White
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Shimmering Text
          AnimatedBuilder(
            animation: _magicController,
            builder: (context, child) {
              return Opacity(
                opacity: 0.5 + (0.5 * math.sin(_magicController.value * math.pi).abs()), 
                child: Text("Conjuring magic...", style: TextStyle(color: neonCyan, fontSize: 13, fontStyle: FontStyle.italic)),
              );
            },
          )
        ],
      ),
    );
  }

  // --- 🌟 UPDATED SLIM GLASS INPUT BAR ---
  Widget _buildSmartGlassInputBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            // ✅ Reduced bottom padding
            bottom: MediaQuery.of(context).padding.bottom + 5, 
            top: 8, // ✅ Reduced top padding
            left: 10, 
            right: 10
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6), // Glassy black base
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 1. Plus Icon
              GestureDetector(
                onTap: () {
                  AppHaptics.lightImpact();
                  setState(() => _isAttachmentOpen = !_isAttachmentOpen);
                },
                child: Container(
                  height: 40, width: 40, // ✅ Slightly smaller
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    color: _isAttachmentOpen ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedRotation(
                    turns: _isAttachmentOpen ? 0.125 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.add, color: Colors.white, size: 26),
                  ),
                ),
              ),
              
              const SizedBox(width: 8),

              // 2. Typing Area (Slimmer & Glassy)
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40, maxHeight: 100), // ✅ Slim height (40)
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08), // ✅ Subtle transparent fill (Glassy)
                    borderRadius: BorderRadius.circular(20), // Slim rounded corners
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)), // Subtle border
                  ),
                  child: Row(
                    children: [
                      // Text Field
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: null,
                          style: const TextStyle(color: Colors.white, fontSize: 15), // ✅ Slightly smaller font
                          cursorColor: neonCyan,
                          decoration: InputDecoration(
                            hintText: "Message...",
                            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onTap: () {
                            setState(() {
                              _isAttachmentOpen = false;
                              _isHistoryOpen = false;
                            });
                          },
                        ),
                      ),
                      
                      // Smart Camera Icon (Hides when typing)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: _hasText 
                          ? const SizedBox.shrink() 
                          : Row(
                              children: [
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: _handleCameraClick,
                                  child: Icon(Icons.camera_alt_rounded, color: Colors.white.withValues(alpha: 0.7), size: 22),
                                ),
                              ],
                            ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // 3. Dynamic Mic / Send Button (Neon Glow)
              GestureDetector(
                onTap: _hasText ? _sendMessage : () {
                  AppHaptics.mediumImpact();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hold to record (Coming Soon)"), duration: Duration(milliseconds: 800)));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 42, width: 42, // ✅ Smaller button size
                  margin: const EdgeInsets.only(bottom: 1),
                  decoration: BoxDecoration(
                    color: _hasText ? neonCyan : const Color(0xFF2C2C2E), 
                    shape: BoxShape.circle,
                    boxShadow: _hasText 
                      ? [BoxShadow(color: neonCyan.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 1)] 
                      : [],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                    child: _hasText
                      ? const Icon(Icons.send_rounded, key: ValueKey('send'), color: Colors.black, size: 20)
                      : const Icon(Icons.mic_rounded, key: ValueKey('mic'), color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- ATTACHMENT POPUP ---
  Widget _buildAttachmentPopup() {
    return Container(
      padding: const EdgeInsets.all(20),
      width: 250, 
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha:0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha:0.5), blurRadius: 25, offset: const Offset(0, 10))
        ]
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildPopupItem(Icons.image, "Gallery", Colors.purpleAccent),
              _buildPopupItem(Icons.insert_drive_file, "File", Colors.indigoAccent),
              _buildPopupItem(Icons.location_on, "Location", Colors.greenAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPopupItem(IconData icon, String label, Color color) {
    return GestureDetector(
      onTap: () { AppHaptics.mediumImpact(); setState(() => _isAttachmentOpen = false); },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha:0.15), border: Border.all(color: color.withValues(alpha:0.3))),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  // --- HISTORY SIDEBAR ---
  Widget _buildHistorySidebar() {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF121212), border: Border(left: BorderSide(color: Colors.white.withValues(alpha:0.1)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 60), 
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [Icon(Icons.history_toggle_off, color: neonCyan, size: 24), const SizedBox(width: 12), const Text("Travel History", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          Expanded(
            child: _chatHistory.isEmpty 
              ? const Center(child: Text("No history yet", style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _chatHistory.length,
                  itemBuilder: (context, index) {
                    final item = _chatHistory[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      title: Text(item['date'], style: const TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: Text(item['preview'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha:0.5), fontSize: 12)),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.white30), onPressed: () { AppHaptics.heavyImpact(); setState(() => _chatHistory.removeAt(index)); }),
                      onTap: () { AppHaptics.lightImpact(); setState(() => _isHistoryOpen = false); },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}