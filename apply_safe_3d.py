import json
import os

file_path = "assets/style.json"

def apply_safe_3d():
    if not os.path.exists(file_path):
        print(f"Error: {file_path} not found.")
        return

    with open(file_path, "r", encoding="utf-8") as f:
        style = json.load(f)

    applied_count = 0

    for layer in style.get("layers", []):
        if layer.get("type") == "fill":
            paint = layer.get("paint", {})
            if paint.get("fill-color") == "#28282B" and paint.get("fill-opacity") == 0.6:
                layer["type"] = "fill-extrusion"
                layer["paint"] = {
                    "fill-extrusion-color": "#28282B",
                    "fill-extrusion-opacity": 0.65,
                    "fill-extrusion-height": [
                        "coalesce",
                        ["get", "height"],
                        0
                    ],
                    "fill-extrusion-base": [
                        "coalesce",
                        ["get", "min_height"],
                        0
                    ]
                }
                applied_count += 1

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(style, f, indent=2)

    print(f"Successfully applied safe 3D coalesce logic to {applied_count} layers.")

if __name__ == "__main__":
    apply_safe_3d()
