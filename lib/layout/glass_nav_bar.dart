import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

class GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTabSelected;
  final VoidCallback onProfileTapped; // 🔥 Naya function add kiya

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onProfileTapped,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    const solidNavColor = Color(0xFF0B0E17);
    const iconColor = Colors.white54;
    const activeColor = Color(0xFF00E5FF);

    return PointerInterceptor(
      child: Container(
        padding: EdgeInsets.only(bottom: bottomPadding > 0 ? bottomPadding + 4 : 16, left: 16, right: 16, top: 4),
        decoration: BoxDecoration(
          color: solidNavColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06), width: 1)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // 🔥 Order wapas pehle jaisi (Home, Search, Bus, Profile)
            _AnimatedNavBarItem(icon: Icons.home_rounded, isActive: currentIndex == 0, activeColor: activeColor, inactiveColor: iconColor, onTap: () => onTabSelected(0)),
            _AnimatedNavBarItem(icon: Icons.search_rounded, isActive: currentIndex == 3, activeColor: activeColor, inactiveColor: iconColor, onTap: () => onTabSelected(3)),
            _AnimatedNavBarItem(icon: CupertinoIcons.bus, isActive: currentIndex == 1, activeColor: activeColor, inactiveColor: iconColor, onTap: () => onTabSelected(1)),
            
            // 🔥 Right me Profile Icon jo sheet open karega
            _AnimatedNavBarItem(
              icon: Icons.person_rounded, 
              isActive: false, // Sheet open hogi isliye isko active dikhane ki zarurat nahi
              activeColor: activeColor, 
              inactiveColor: iconColor, 
              onTap: onProfileTapped,
            ),
          ],
        ),
      ),
    );
  }
}

// _AnimatedNavBarItem class pehle jaisi hi rahegi, usme koi change nahi hai
class _AnimatedNavBarItem extends StatefulWidget {
  final IconData icon; final bool isActive; final Color activeColor; final Color inactiveColor; final VoidCallback onTap;
  const _AnimatedNavBarItem({required this.icon, required this.isActive, required this.activeColor, required this.inactiveColor, required this.onTap});
  @override State<_AnimatedNavBarItem> createState() => __AnimatedNavBarItemState();
}
class __AnimatedNavBarItemState extends State<_AnimatedNavBarItem> {
  double _scale = 1.0;
  void _onTapDown(_) => setState(() => _scale = 0.85);
  void _onTapUp(_) { setState(() => _scale = 1.0); Future.microtask(widget.onTap); }
  void _onTapCancel() => setState(() => _scale = 1.0);
  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown, onTapUp: _onTapUp, onTapCancel: _onTapCancel, behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _scale, duration: const Duration(milliseconds: 150), curve: Curves.easeOutBack,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: Icon(widget.icon, color: widget.isActive ? widget.activeColor : widget.inactiveColor, size: 28)),
      ),
    );
  }
}