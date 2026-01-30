#!/usr/bin/env python3
"""
Test d'inférence Chandra MLX pour CASS
Teste le modèle converti avec une image de test
"""

import subprocess
import sys
import time
from pathlib import Path

# Chemin du modèle
MODEL_PATH = Path.home() / "Library/Application Support/CASS/Models/chandra-mlx"

def check_model():
    """Vérifie que le modèle est installé"""
    if not MODEL_PATH.exists():
        print(f"ERREUR: Modèle non trouvé: {MODEL_PATH}")
        return False

    # Vérifier les fichiers essentiels
    required = ["config.json", "model.safetensors.index.json"]
    for f in required:
        if not (MODEL_PATH / f).exists():
            print(f"ERREUR: Fichier manquant: {f}")
            return False

    print(f"Modèle trouvé: {MODEL_PATH}")

    # Lister les fichiers
    files = list(MODEL_PATH.glob("*"))
    total_size = sum(f.stat().st_size for f in files if f.is_file())
    print(f"   Fichiers: {len(files)}")
    print(f"   Taille totale: {total_size / 1e9:.2f} GB")

    return True

def create_test_image():
    """Crée une image de test simple avec du texte manuscrit simulé"""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Installation de Pillow...")
        subprocess.run([sys.executable, "-m", "pip", "install", "Pillow"], check=True)
        from PIL import Image, ImageDraw, ImageFont

    # Créer une image blanche avec du texte
    img = Image.new('RGB', (800, 200), color='white')
    draw = ImageDraw.Draw(img)

    # Texte de test (simulant une écriture)
    test_text = "Bonjour, ceci est un test d'OCR manuscrit."

    # Utiliser une police système
    try:
        # Essayer une police manuscrite sur macOS
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Bradley Hand Bold.ttf", 40)
    except:
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 40)
        except:
            font = ImageFont.load_default()

    draw.text((50, 70), test_text, fill='darkblue', font=font)

    # Sauvegarder
    test_path = Path("/tmp/cass_test_ocr.png")
    img.save(test_path)
    print(f"Image de test créée: {test_path}")

    return str(test_path)

def test_inference(image_path: str):
    """Teste l'inférence avec mlx-vlm"""
    print("\n" + "="*60)
    print("Test d'inférence Chandra MLX")
    print("="*60)

    try:
        from mlx_vlm import load, generate
        from mlx_vlm.prompt_utils import apply_chat_template
        from mlx_vlm.utils import load_config
    except ImportError as e:
        print(f"ERREUR: mlx-vlm non installé: {e}")
        return False

    print(f"\nChargement du modèle...")
    start_load = time.time()

    try:
        # Charger le modèle et le processeur
        model, processor = load(str(MODEL_PATH))
        load_time = time.time() - start_load
        print(f"   Modèle chargé en {load_time:.1f}s")
    except Exception as e:
        print(f"ERREUR lors du chargement: {e}")
        import traceback
        traceback.print_exc()
        return False

    # Prompt pour OCR - format Qwen3-VL
    user_prompt = "Transcribe the handwritten text in this image exactly as written."

    print(f"\nImage: {image_path}")
    print(f"Prompt: {user_prompt}")

    # Format Qwen3-VL avec balises spéciales
    # <|vision_start|><|image_pad|><|vision_end|> sera remplacé par le processeur
    formatted_prompt = (
        "<|im_start|>system\n"
        "You are a helpful assistant specialized in OCR (Optical Character Recognition). "
        "Transcribe text from images accurately.<|im_end|>\n"
        "<|im_start|>user\n"
        "<|vision_start|><|image_pad|><|vision_end|>"
        f"{user_prompt}<|im_end|>\n"
        "<|im_start|>assistant\n"
    )

    print(f"\nGénération en cours...")
    start_gen = time.time()

    try:
        output = generate(
            model,
            processor,
            image=image_path,
            prompt=formatted_prompt,
            max_tokens=256,
            temp=0.1,  # Basse température pour OCR précis
            verbose=False
        )
        gen_time = time.time() - start_gen

        # Extraire le texte de GenerationResult
        if hasattr(output, 'text'):
            text_result = output.text
            prompt_tps = getattr(output, 'prompt_tps', 0)
            gen_tps = getattr(output, 'generation_tps', 0)
            peak_mem = getattr(output, 'peak_memory', 0)
        else:
            text_result = str(output)
            prompt_tps = gen_tps = peak_mem = 0

        print(f"\n" + "-"*60)
        print("RÉSULTAT OCR:")
        print("-"*60)
        print(text_result)
        print("-"*60)
        print(f"\nTemps de génération: {gen_time:.1f}s")
        if gen_tps > 0:
            print(f"Tokens/s: {gen_tps:.1f}")
        if peak_mem > 0:
            print(f"Mémoire pic: {peak_mem:.2f} GB")

        return True

    except Exception as e:
        print(f"ERREUR lors de la génération: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    print("="*60)
    print("CASS - Test d'inférence Chandra")
    print("="*60)

    # Vérifier le modèle
    if not check_model():
        sys.exit(1)

    # Vérifier si une image est fournie en argument
    if len(sys.argv) > 1:
        image_path = sys.argv[1]
        if not Path(image_path).exists():
            print(f"ERREUR: Image non trouvée: {image_path}")
            sys.exit(1)
    else:
        # Créer une image de test
        print("\nAucune image fournie, création d'une image de test...")
        image_path = create_test_image()

    # Tester l'inférence
    success = test_inference(image_path)

    if success:
        print("\n" + "="*60)
        print("TEST RÉUSSI!")
        print("="*60)
    else:
        print("\n" + "="*60)
        print("TEST ÉCHOUÉ")
        print("="*60)
        sys.exit(1)

if __name__ == "__main__":
    main()
