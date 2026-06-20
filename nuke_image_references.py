import json
import os

file_path = "assets/style.json"

def nuke_images():
    if not os.path.exists(file_path):
        print(f"Error: {file_path} not found.")
        return

    with open(file_path, "r", encoding="utf-8") as f:
        style = json.load(f)

    keys_to_remove = ["icon-image", "background-pattern", "fill-pattern", "line-pattern"]
    removed_count = 0

    for layer in style.get("layers", []):
        for obj_key in ["paint", "layout"]:
            if obj_key in layer and isinstance(layer[obj_key], dict):
                for key in keys_to_remove:
                    if key in layer[obj_key]:
                        del layer[obj_key][key]
                        removed_count += 1
        
        # Also ensure icon-optional is set for all symbol layers
        if layer.get("type") == "symbol":
            if "layout" not in layer:
                layer["layout"] = {}
            layer["layout"]["icon-optional"] = True

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(style, f, indent=2)

    print(f"Nuked {removed_count} image pattern/icon references.")

if __name__ == "__main__":
    nuke_images()
