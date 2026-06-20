import json
import os

file_path = "assets/style.json"

def revert_3d_to_2d():
    if not os.path.exists(file_path):
        print(f"Error: {file_path} not found.")
        return

    with open(file_path, "r", encoding="utf-8") as f:
        style = json.load(f)

    reverted_count = 0

    for layer in style.get("layers", []):
        if layer.get("type") == "fill-extrusion":
            layer["type"] = "fill"
            layer["paint"] = {
                "fill-color": "#28282B",
                "fill-opacity": 0.6
            }
            reverted_count += 1

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(style, f, indent=2)

    print(f"Successfully reverted {reverted_count} 3D fill-extrusion layers back to 2D fill.")

if __name__ == "__main__":
    revert_3d_to_2d()
