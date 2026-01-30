#!/usr/bin/env python3
"""
CASS - Chandra MLX Inference Engine
Script appelé par ChandraService.swift pour l'OCR manuscrit

Usage:
    python3 chandra_inference.py <image_path> [--json]

Output (JSON):
    {
        "success": true,
        "text": "transcribed text...",
        "lines": ["line1", "line2", ...],
        "bounding_boxes": [{"text": "...", "x": 0, "y": 0, "width": 100, "height": 20}, ...],
        "confidence": 0.95,
        "processing_time": 3.2
    }
"""

import json
import re
import sys
import time
from pathlib import Path

# Chemin du modèle
MODEL_PATH = Path.home() / "Library/Application Support/CASS/Models/chandra-mlx"

# Cache global pour éviter de recharger le modèle
_model_cache = {"model": None, "processor": None}

# Constante de Chandra : les bounding boxes sont normalisées à 0-1024
BBOX_SCALE = 1024

# Prompt OCR_LAYOUT exact de Chandra
OCR_LAYOUT_PROMPT = """
OCR this image to HTML, arranged as layout blocks.  Each layout block should be a div with the data-bbox attribute representing the bounding box of the block in [x0, y0, x1, y1] format.  Bboxes are normalized 0-{bbox_scale}. The data-label attribute is the label for the block.

Use the following labels:
- Caption
- Footnote
- Equation-Block
- List-Group
- Page-Header
- Page-Footer
- Image
- Section-Header
- Table
- Text
- Complex-Block
- Code-Block
- Form
- Table-Of-Contents
- Figure

Only use these tags ['math', 'br', 'i', 'b', 'u', 'del', 'sup', 'sub', 'table', 'tr', 'td', 'p', 'th', 'div', 'pre', 'h1', 'h2', 'h3', 'h4', 'h5', 'ul', 'ol', 'li', 'input', 'a', 'span', 'img', 'hr', 'tbody', 'small', 'caption', 'strong', 'thead', 'big', 'code'], and these attributes ['class', 'colspan', 'rowspan', 'display', 'checked', 'type', 'border', 'value', 'style', 'href', 'alt', 'align'].

Guidelines:
* Inline math: Surround math with <math>...</math> tags. Math expressions should be rendered in KaTeX-compatible LaTeX. Use display for block math.
* Tables: Use colspan and rowspan attributes to match table structure.
* Formatting: Maintain consistent formatting with the image, including spacing, indentation, subscripts/superscripts, and special characters.
* Images: Include a description of any images in the alt attribute of an <img> tag. Do not fill out the src property.
* Forms: Mark checkboxes and radio buttons properly.
* Text: join lines together properly into paragraphs using <p>...</p> tags.  Use <br> tags for line breaks within paragraphs, but only when absolutely necessary to maintain meaning.
* Use the simplest possible HTML structure that accurately represents the content of the block.
* Make sure the text is accurate and easy for a human to read and interpret.  Reading order should be correct and natural.
""".strip()


def parse_layout_blocks(raw_html: str, image_width: int, image_height: int) -> list[dict]:
    """
    Parse le HTML Chandra et extrait les bounding boxes avec les bonnes coordonnées.
    Les coordonnées sont mises à l'échelle de 0-1024 vers les dimensions réelles de l'image.

    Basé sur chandra/output.py:parse_layout()
    """
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(raw_html, "html.parser")
    top_level_divs = soup.find_all("div", recursive=False)

    # Facteurs de mise à l'échelle
    width_scaler = image_width / BBOX_SCALE
    height_scaler = image_height / BBOX_SCALE

    blocks = []

    for div in top_level_divs:
        bbox_str = div.get("data-bbox")
        label = div.get("data-label", "Text")

        # Parser le bbox
        bbox = None
        if bbox_str:
            try:
                # Essayer JSON d'abord: [x0, y0, x1, y1]
                bbox = json.loads(bbox_str)
                assert len(bbox) == 4
            except (json.JSONDecodeError, AssertionError):
                try:
                    # Essayer format espace séparé: "x0 y0 x1 y1"
                    bbox = list(map(int, bbox_str.split()))
                    assert len(bbox) == 4
                except (ValueError, AssertionError):
                    bbox = None

        if not bbox:
            # Ignorer les blocs sans bbox valide
            continue

        # Convertir en entiers
        bbox = list(map(int, bbox))

        # Mettre à l'échelle vers les coordonnées réelles de l'image
        x1 = max(0, int(bbox[0] * width_scaler))
        y1 = max(0, int(bbox[1] * height_scaler))
        x2 = min(int(bbox[2] * width_scaler), image_width)
        y2 = min(int(bbox[3] * height_scaler), image_height)

        # Calculer width et height
        width = x2 - x1
        height = y2 - y1

        # Ignorer les boxes invalides
        if width <= 0 or height <= 0:
            continue

        # Extraire le texte
        text = div.get_text(separator=" ", strip=True)

        if text:
            blocks.append({
                "text": text,
                "x": x1,
                "y": y1,
                "width": width,
                "height": height,
                "label": label,
                "estimated": False
            })

    return blocks


def extract_text_from_html(raw_html: str) -> tuple[str, list[str]]:
    """Extrait le texte propre du HTML Chandra"""
    try:
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(raw_html, "html.parser")

        # Extraire le texte de chaque div de premier niveau
        texts = []
        for div in soup.find_all("div", recursive=False):
            text = div.get_text(separator=" ", strip=True)
            if text:
                texts.append(text)

        full_text = "\n".join(texts)
        return full_text, texts
    except ImportError:
        # Fallback sans BeautifulSoup
        text = re.sub(r'<[^>]+>', ' ', raw_html)
        text = re.sub(r'\s+', ' ', text).strip()
        lines = [line.strip() for line in text.split('\n') if line.strip()]
        return text, lines


def load_model():
    """Charge le modèle (avec cache)"""
    if _model_cache["model"] is not None:
        return _model_cache["model"], _model_cache["processor"]

    from mlx_vlm import load
    model, processor = load(str(MODEL_PATH))
    _model_cache["model"] = model
    _model_cache["processor"] = processor
    return model, processor


def resize_image_if_needed(image_path: str, max_pixels: int = 2048 * 2048) -> tuple[str, tuple[int, int]]:
    """
    Redimensionne l'image si elle est trop grande pour éviter les erreurs Metal.
    Retourne: (chemin_image, (largeur, hauteur))
    """
    try:
        from PIL import Image
    except ImportError:
        return image_path, (0, 0)

    img = Image.open(image_path)
    original_width, original_height = img.size
    total_pixels = original_width * original_height

    if total_pixels <= max_pixels:
        return image_path, (original_width, original_height)

    # Calculer le facteur de réduction
    scale = (max_pixels / total_pixels) ** 0.5
    new_width = int(original_width * scale)
    new_height = int(original_height * scale)

    print(f"[INFO] Redimensionnement: {original_width}x{original_height} -> {new_width}x{new_height}", file=sys.stderr)

    # Redimensionner
    img_resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)

    # Sauvegarder dans un fichier temporaire
    temp_path = Path(image_path).parent / f"resized_{Path(image_path).name}"
    img_resized.save(temp_path, quality=95)

    return str(temp_path), (new_width, new_height)


def run_inference(image_path: str) -> dict:
    """Exécute l'inférence OCR sur une image"""
    start_time = time.time()

    # Vérifier que l'image existe
    if not Path(image_path).exists():
        return {
            "success": False,
            "error": f"Image non trouvée: {image_path}"
        }

    # Vérifier que le modèle existe
    if not MODEL_PATH.exists():
        return {
            "success": False,
            "error": f"Modèle non trouvé: {MODEL_PATH}"
        }

    # Redimensionner si trop grande et obtenir les dimensions finales
    processed_image_path, (image_width, image_height) = resize_image_if_needed(image_path)

    try:
        from mlx_vlm import generate

        # Charger le modèle
        model, processor = load_model()
        load_time = time.time() - start_time

        # Utiliser le prompt OCR_LAYOUT exact de Chandra
        prompt = OCR_LAYOUT_PROMPT.format(bbox_scale=BBOX_SCALE)

        # Format Qwen3-VL pour MLX
        formatted_prompt = (
            "<|im_start|>system\n"
            "You are Chandra, a powerful OCR system.<|im_end|>\n"
            "<|im_start|>user\n"
            "<|vision_start|><|image_pad|><|vision_end|>"
            f"{prompt}<|im_end|>\n"
            "<|im_start|>assistant\n"
        )

        # Inférence
        gen_start = time.time()
        output = generate(
            model,
            processor,
            image=processed_image_path,
            prompt=formatted_prompt,
            max_tokens=4096,  # Plus de tokens pour layout complet
            temp=0.1,
            verbose=False
        )
        gen_time = time.time() - gen_start

        # Extraire le texte brut
        if hasattr(output, 'text'):
            raw_html = output.text
            tokens_per_second = getattr(output, 'generation_tps', 0)
            peak_memory = getattr(output, 'peak_memory', 0)
        else:
            raw_html = str(output)
            tokens_per_second = 0
            peak_memory = 0

        # Parser les bounding boxes avec mise à l'échelle correcte
        bounding_boxes = parse_layout_blocks(raw_html, image_width, image_height)

        # Extraire le texte
        if bounding_boxes:
            text = "\n".join([box["text"] for box in bounding_boxes])
            lines = [box["text"] for box in bounding_boxes]
        else:
            # Fallback si pas de boxes parsées
            text, lines = extract_text_from_html(raw_html)

        # Estimation de confiance basée sur le nombre de boxes trouvées
        confidence = 0.95 if bounding_boxes else 0.7

        total_time = time.time() - start_time

        return {
            "success": True,
            "text": text,
            "lines": lines,
            "bounding_boxes": bounding_boxes,
            "confidence": confidence,
            "processing_time": total_time,
            "load_time": load_time,
            "generation_time": gen_time,
            "tokens_per_second": tokens_per_second,
            "peak_memory_gb": peak_memory,
            "image_size": [image_width, image_height],
            "raw_html": raw_html  # Pour debug
        }

    except Exception as e:
        import traceback
        return {
            "success": False,
            "error": str(e),
            "traceback": traceback.format_exc()
        }


def main():
    if len(sys.argv) < 2:
        print(json.dumps({
            "success": False,
            "error": "Usage: python3 chandra_inference.py <image_path>"
        }))
        sys.exit(1)

    image_path = sys.argv[1]
    result = run_inference(image_path)

    # Toujours sortir en JSON pour Swift
    print(json.dumps(result, ensure_ascii=False, indent=2))

    sys.exit(0 if result.get("success") else 1)


if __name__ == "__main__":
    main()
