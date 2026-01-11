import 'package:flutter/material.dart';

// ✅ Data Model
class PlaceItem {
  final String id;
  final String title; 
  final String subtitle;
  final IconData iconData;
  final Color color;
  bool isPinned;

  PlaceItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconData,
    required this.color,
    this.isPinned = false,
  });
}

class SuggestedGlassCard extends StatelessWidget {
  final PlaceItem item;
  final VoidCallback onTap;
  final VoidCallback onDismissed; 
  final VoidCallback onPinned;    

  const SuggestedGlassCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDismissed,
    required this.onPinned,
  });

  @override
  Widget build(BuildContext context) {
    final glowColor = item.color;
    final actionColor = item.color;

    return Dismissible(
      key: Key(item.id), 
      direction: DismissDirection.horizontal, 
      
      // ✅ LEFT SWIPE (Not Interested)
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20.0),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.thumb_down_off_alt_rounded, color: Colors.white, size: 30),
            SizedBox(height: 4),
            Text('Not Interested', style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),

      // ✅ RIGHT SWIPE (Pin)
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, color: Colors.white, size: 30),
            const SizedBox(height: 4),
            Text(item.isPinned ? 'Pinned!' : 'Pin to Tour', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),

      // ✅ LOGIC
      onDismissed: (direction) {
        if (direction == DismissDirection.startToEnd) {
          onDismissed();
        } else {
          onPinned();
        }
      },
      
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          // Right Swipe: Sirf Pin karna hai, Card remove nahi karna
          onPinned();
          return false; 
        }
        // Left Swipe: Card remove karna hai
        return true; 
      },

      // ✅ OPTIMIZED CARD DESIGN (Performance Fix)
      // Removed BackdropFilter to prevent Lag on scrolling
      child: Container(
        height: 85,
        decoration: BoxDecoration(
          // Fake Glass Effect (Faster GPU Rendering)
          color: const Color(0xFF1E1E1E).withValues(alpha: 0.7), 
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.05),
              Colors.white.withValues(alpha: 0.01),
            ],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            splashColor: glowColor.withValues(alpha: 0.2),
            child: Row(
              children: [
                const SizedBox(width: 16),
                
                // Icon Container
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                      color: glowColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: glowColor.withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: glowColor.withValues(alpha: 0.15),
                          blurRadius: 12,
                          spreadRadius: -2,
                        )
                      ]
                  ),
                  child: Center(child: Icon(item.iconData, color: Colors.white, size: 28)),
                ),
                
                const SizedBox(width: 16),
                
                // Text Content
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title, 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                
                // Visit Button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    'Visit',
                    style: TextStyle(
                      color: actionColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
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