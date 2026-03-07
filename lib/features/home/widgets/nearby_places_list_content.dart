import 'dart:math';
import 'package:flutter/material.dart';
import '../services/wikipedia_service.dart';

class NearbyPlacesListContent extends StatefulWidget {
  final double destLat;
  final double destLng;
  final double userLat; 
  final double userLng;

  const NearbyPlacesListContent({
    super.key,
    required this.destLat,
    required this.destLng,
    required this.userLat,
    required this.userLng,
  });

  @override
  State<NearbyPlacesListContent> createState() => _NearbyPlacesListContentState();
}

class _NearbyPlacesListContentState extends State<NearbyPlacesListContent> {
  List<Map<String, dynamic>> _places = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPlaces();
  }

  void _fetchPlaces() async {
    final places = await WikipediaService.fetchNearbyPlaces(widget.destLat, widget.destLng);
    if (mounted) {
      setState(() {
        _places = places;
        _isLoading = false;
      });
    }
  }

  // Distance Calculator
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); 
  }

  @override
  Widget build(BuildContext context) {
    const Color neonCyan = Color(0xFF00E5FF);

    if (_isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator(color: neonCyan)),
      );
    }

    if (_places.isEmpty) {
      return const SizedBox(
        height: 300,
        child: Center(child: Text("No places found.", style: TextStyle(color: Colors.white54))),
      );
    }

    return ListView.builder(
      shrinkWrap: true, // ✅ Sheet height adjust karne me help karega
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 85.0, left: 20, right: 20, bottom: 30),
      itemCount: _places.length,
      itemBuilder: (context, index) {
        final place = _places[index];
        
        // 🔥 THE FIX: Yaha hum safely parse kar rahe hain aur Null check laga rahe hain
        double placeLat = place['lat'] != null ? (place['lat'] as num).toDouble() : widget.destLat;
        double placeLng = place['lon'] != null ? (place['lon'] as num).toDouble() : widget.destLng;

        double distance = _calculateDistance(widget.userLat, widget.userLng, placeLat, placeLng);
        
        double mockRating = 4.0 + (place['title'].toString().length % 10) / 10.0;
        int mockTemp = 15 + (place['title'].toString().length % 15);

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  place['imageUrl'],
                  width: 80, height: 80, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 80, height: 80, color: Colors.grey.shade800),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place['title'],
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.social_distance, color: Colors.grey.shade400, size: 14),
                        const SizedBox(width: 4),
                        Text("${distance.toStringAsFixed(1)} km from you", style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: neonCyan.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            children: [
                              Icon(Icons.star, color: neonCyan, size: 12),
                              const SizedBox(width: 4),
                              Text(mockRating.toStringAsFixed(1), style: TextStyle(color: neonCyan, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            children: [
                              const Icon(Icons.thermostat, color: Colors.orange, size: 12),
                              const SizedBox(width: 4),
                              Text("$mockTemp°C", style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }
}