import json
import requests
import sys
import os

api_key = "LXLK4nwQMwacpTZhol7QHc3RPet3tUOkb76reivs"
url = f"https://api.olamaps.io/tiles/vector/v1/styles/default-dark-standard/style.json?api_key={api_key}"

data = None

# If style.json doesn't exist locally, fetch it from the API
if not os.path.exists('style.json'):
    print("style.json not found locally. Fetching from Ola Maps API...")
    try:
        response = requests.get(url, timeout=15)
        response.raise_for_status()
        data = response.json()
        
        # Inject API keys for sprites, glyphs, and tiles
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
        print(f"Failed to fetch style: {e}")
        sys.exit(1)
else:
    print("Loading local style.json...")
    with open('style.json', 'r') as f:
        data = json.load(f)

layers = data.get('layers', [])
for layer in layers:
    id_str = layer.get('id', '').lower()
    sl_str = layer.get('source-layer', '').lower()
    t = layer.get('type', '')
    
    # Task 2: Inject Soft 3D Buildings
    if ('building' in id_str or 'building' in sl_str) and t in ['fill', 'fill-extrusion']:
        layer['type'] = 'fill-extrusion'
        if 'paint' not in layer:
            layer['paint'] = {}
            
        layer['paint']['fill-extrusion-color'] = '#28282B'
        layer['paint']['fill-extrusion-opacity'] = 0.65
        layer['paint']['fill-extrusion-height'] = ["get", "height"]
        layer['paint']['fill-extrusion-base'] = ["get", "min_height"]
        
        # Remove old flat fill properties safely
        for key in ['fill-color', 'fill-opacity', 'fill-outline-color']:
            layer['paint'].pop(key, None)
            
    # Task 1: Safe Recolor (Modify ONLY paint properties based on keywords)
    if 'paint' in layer:
        paint = layer['paint']
        
        # Background / Land -> #1C1C1E
        if t == 'background':
            paint['background-color'] = '#1C1C1E'
        elif any(k in id_str or k in sl_str for k in ['land', 'background']):
            if t == 'fill':
                paint['fill-color'] = '#1C1C1E'
                
        # Water -> #0F172A
        if any(k in id_str or k in sl_str for k in ['water', 'river']):
            if t == 'fill':
                paint['fill-color'] = '#0F172A'
            elif t == 'line':
                paint['line-color'] = '#0F172A'
                
        # Parks / Greenery -> #1A2621
        if any(k in id_str or k in sl_str for k in ['park', 'forest', 'green', 'recreation']):
            if t == 'fill':
                paint['fill-color'] = '#1A2621'
                
        # Roads / Highways
        if any(k in id_str or k in sl_str for k in ['road', 'highway', 'street', 'path']):
            if t == 'line':
                # Remove casing layers or make very thin
                if 'casing' in id_str or 'outline' in id_str:
                    paint['line-width'] = 0.1
                    paint['line-color'] = '#1C1C1E' # Blend with background to hide harsh borders
                else:
                    if any(k in id_str or k in sl_str for k in ['minor', 'service', 'track']):
                        paint['line-color'] = '#2C2C2E'
                    else:
                        paint['line-color'] = '#3A3A3C'
                
        # Text / Labels
        if any(k in id_str or k in sl_str for k in ['label', 'text']) or t == 'symbol':
            if 'text-color' in paint:
                paint['text-color'] = '#EBEBF5'
            if 'text-halo-color' in paint or 'text-color' in paint:
                paint['text-halo-color'] = '#000000'
                paint['text-halo-width'] = 1.0

with open('style.json', 'w') as f:
    json.dump(data, f, indent=2)

print("Premium Apple Maps Dark Mode applied successfully to style.json")
