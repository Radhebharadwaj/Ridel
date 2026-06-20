import json
import os

file_path = "assets/style.json"

def apply_brahmastra():
    if not os.path.exists(file_path):
        print(f"Error: {file_path} not found.")
        return

    with open(file_path, "r", encoding="utf-8") as f:
        style = json.load(f)

    # 1. Root Sprite Nuke
    if "sprite" in style:
        del style["sprite"]
        print("Nuked root 'sprite' property.")

    scrubbed_keys = 0
    removed_layers = 0

    new_layers = []

    for layer in style.get("layers", []):
        # 2. Aggressive Key Scrubbing
        for obj_key in ["layout", "paint"]:
            if obj_key in layer and isinstance(layer[obj_key], dict):
                # Collect keys to delete to avoid modifying dict while iterating
                keys_to_delete = [
                    k for k in layer[obj_key].keys()
                    if "icon" in k or "pattern" in k
                ]
                for k in keys_to_delete:
                    del layer[obj_key][k]
                    scrubbed_keys += 1

        # 3. Empty Symbol Nuke
        if layer.get("type") == "symbol":
            # If it has no text-field, it was purely an icon layer
            layout = layer.get("layout", {})
            if "text-field" not in layout:
                removed_layers += 1
                continue # Do not add to new_layers

        new_layers.append(layer)

    style["layers"] = new_layers

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(style, f, indent=2)

    print(f"Scrubbed {scrubbed_keys} icon/pattern keys.")
    print(f"Deleted {removed_layers} empty symbol layers.")
    print("Brahmastra execution complete.")

if __name__ == "__main__":
    apply_brahmastra()
