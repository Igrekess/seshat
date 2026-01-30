#!/usr/bin/env python3
"""
Test visuel des bounding boxes Chandra.
Dessine les boxes sur l'image pour vérification.
"""

import json
import sys
from pathlib import Path

def draw_boxes_on_image(image_path: str, output_path: str = None):
    """Exécute l'inférence et dessine les boxes sur l'image"""
    from PIL import Image, ImageDraw, ImageFont

    # Importer et exécuter l'inférence
    from chandra_inference import run_inference

    result = run_inference(image_path)

    if not result.get("success"):
        print(f"Erreur: {result.get('error')}")
        return

    # Charger l'image
    img = Image.open(image_path)
    draw = ImageDraw.Draw(img)

    # Dessiner chaque bounding box
    boxes = result.get("bounding_boxes", [])
    print(f"Nombre de boxes: {len(boxes)}")
    print(f"Dimensions image: {img.size}")

    colors = {
        "Text": "red",
        "Section-Header": "blue",
        "Page-Footer": "gray",
        "Page-Header": "gray",
        "Table": "green",
        "Image": "purple",
        "Figure": "purple",
    }

    for i, box in enumerate(boxes):
        x1 = box["x"]
        y1 = box["y"]
        x2 = x1 + box["width"]
        y2 = y1 + box["height"]
        label = box.get("label", "Text")
        color = colors.get(label, "red")

        # Dessiner le rectangle
        draw.rectangle([x1, y1, x2, y2], outline=color, width=2)

        # Dessiner le label
        text = f"{i+1}. {label}"
        draw.text((x1, y1 - 15), text, fill="blue")

        # Afficher info dans console
        print(f"  Box {i+1}: [{x1},{y1}] -> [{x2},{y2}] ({box['width']}x{box['height']}) - {label}")
        print(f"    Text: {box['text'][:60]}...")

    # Sauvegarder
    if output_path is None:
        output_path = str(Path(image_path).parent / f"debug_boxes_{Path(image_path).stem}.jpg")

    img.save(output_path, quality=95)
    print(f"\nImage sauvegardée: {output_path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python test_bounding_boxes.py <image_path> [output_path]")
        sys.exit(1)

    image_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else None

    draw_boxes_on_image(image_path, output_path)
