import json
import os

file_path = "assets/style.json"

def apply_zoom_constraints():
    if not os.path.exists(file_path):
        print(f"Error: {file_path} not found.")
        return

    with open(file_path, "r", encoding="utf-8") as f:
        style = json.load(f)

    minor_keywords = ["poi", "shop", "food", "restaurant", "hotel", "cafe", "atm", "bank"]
    medium_keywords = ["hospital", "transit", "bus", "metro", "park"]
    keep_keywords = ["city", "country", "state", "town"]

    modified_count = 0

    for layer in style.get("layers", []):
        if layer.get("type") == "symbol":
            layer_id = layer.get("id", "").lower()
            
            # Skip city/country labels
            if any(k in layer_id for k in keep_keywords):
                continue
                
            # Apply Medium POIs
            if any(k in layer_id for k in medium_keywords):
                layer["minzoom"] = 13
                modified_count += 1
                continue
                
            # Apply Minor POIs
            if any(k in layer_id for k in minor_keywords):
                layer["minzoom"] = 15
                modified_count += 1
                continue

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(style, f, indent=2)

    print(f"Successfully applied zoom constraints to {modified_count} layers.")

if __name__ == "__main__":
    apply_zoom_constraints()
