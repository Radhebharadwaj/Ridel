import json
import requests
import sys

print("Discarding old style.json and fetching fresh from Ola Maps API...")

api_key = "LXLK4nwQMwacpTZhol7QHc3RPet3tUOkb76reivs"
url = f"https://api.olamaps.io/tiles/vector/v1/styles/default-dark-standard/style.json?api_key={api_key}"

try:
    response = requests.get(url, timeout=15)
    response.raise_for_status()
    data = response.json()
    
    if data.get('sprite') and '?api_key=' not in data['sprite']:
        data['sprite'] = f"{data['sprite'].split('?')[0]}?api_key={api_key}"
    if data.get('glyphs') and '?api_key=' not in data['glyphs']:
        data['glyphs'] = f"{data['glyphs'].split('?')[0]}?api_key={api_key}"
    if 'sources' in data:
        for k, source in data['sources'].items():
            if 'url' in source:
                base = source['url'].split('?')[0].replace('.json', '/{z}/{x}/{y}.pbf')
                source['tiles'] = [f"{base}?api_key={api_key}"]
                del source['url']
            elif 'tiles' in source:
                source['tiles'] = [f"{t.split('?')[0]}?api_key={api_key}" if '?api_key=' not in t else t for t in source['tiles']]
except Exception as e:
    print(f"Failed to fetch fresh style: {e}")
    sys.exit(1)

layers = data.get('layers', [])
for layer in layers:
    id_str = layer.get('id', '').lower()
    t = layer.get('type', '')
    
    if 'paint' not in layer:
        layer['paint'] = {}
        
    paint = layer['paint']
    
    # Task 3: 3D Buildings (Type-Safe)
    if t == "fill" and "building" in id_str:
        layer["type"] = "fill-extrusion"
        layer["paint"] = {
            "fill-extrusion-color": "#28282B",
            "fill-extrusion-opacity": 0.65,
            "fill-extrusion-height": ["get", "height"],
            "fill-extrusion-base": ["get", "min_height"]
        }
        continue # Skip other processing for buildings

    # Task 2: Type-Safe Recolor
    # Background
    if t == "background":
        paint["background-color"] = "#1C1C1E"
        
    # Water
    elif t == "fill" and any(k in id_str for k in ["water", "river", "ocean"]):
        paint["fill-color"] = "#0F172A"
        
    # Greenery
    elif t == "fill" and any(k in id_str for k in ["park", "green", "forest"]):
        paint["fill-color"] = "#1A2621"
        
    # Base Land
    elif t == "fill" and any(k in id_str for k in ["land", "earth"]):
        paint["fill-color"] = "#1C1C1E"
        
    # Roads
    elif t == "line" and any(k in id_str for k in ["road", "highway", "street"]):
        paint["line-color"] = "#3A3A3C"
        if "case" in id_str or "casing" in id_str:
            paint["line-width"] = 0

with open('assets/style.json', 'w') as f:
    json.dump(data, f, indent=2)

print("Type-Safe Premium Dark Mode applied successfully to assets/style.json")
