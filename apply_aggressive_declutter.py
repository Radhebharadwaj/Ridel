import json
import os

file_path = "assets/style.json"

def apply_aggressive_declutter():
    if not os.path.exists(file_path):
        print(f"Error: {file_path} not found.")
        return

    with open(file_path, "r", encoding="utf-8") as f:
        style = json.load(f)

    essential_geography = ["country", "state", "city", "town", "district", "village"]
    navigation_labels = ["road", "highway", "street", "path", "water"]

    optional_icons_count = 0
    minzoom_count = 0

    for layer in style.get("layers", []):
        if layer.get("type") == "symbol":
            layer_id = layer.get("id", "").lower()
            
            # Fix 1: Prevent Crashes (icon-optional)
            if "layout" not in layer:
                layer["layout"] = {}
            # Setting icon-optional to True prevents missing sprites from dropping the entire text label or crashing
            layer["layout"]["icon-optional"] = True
            optional_icons_count += 1
            
            # Fix 2: Aggressive Decluttering
            if any(k in layer_id for k in essential_geography):
                continue
                
            if any(k in layer_id for k in navigation_labels):
                continue
                
            # ELSE (Catch-All for POIs):
            layer["minzoom"] = 16
            minzoom_count += 1

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(style, f, indent=2)

    print(f"Success! Set icon-optional=True on {optional_icons_count} layers.")
    print(f"Forced minzoom=16 on {minzoom_count} POI layers.")

if __name__ == "__main__":
    apply_aggressive_declutter()
