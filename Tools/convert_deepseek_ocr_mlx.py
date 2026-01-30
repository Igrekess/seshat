#!/usr/bin/env python3
"""
convert_deepseek_ocr_mlx.py

Convertit le modèle DeepSeek-OCR-2 vers le format MLX avec quantization.

DeepSeek-OCR-2 est un modèle OCR léger optimisé pour les machines avec 8GB de RAM.
Bon compromis entre qualité et ressources.

Usage:
    python convert_deepseek_ocr_mlx.py --output ~/Library/Application\ Support/CASS/Models/deepseek-ocr-mlx
    python convert_deepseek_ocr_mlx.py --bits 8 --output ./deepseek-ocr-mlx-8bit

Prérequis:
    pip install mlx-lm mlx-vlm huggingface_hub transformers torch

Spécifications DeepSeek-OCR-2:
    - Taille: 3B params
    - Score olmOCR-bench: 75.4 (manuscrit)
    - RAM requise: ~2.5GB (4-bit) | ~5GB (8-bit)
    - Mac minimum: 8GB RAM
    - Licence: Apache 2.0 (usage libre)
    - Source: https://huggingface.co/deepseek-ai/DeepSeek-OCR-2

Points forts:
    - Léger et rapide
    - Fonctionne sur Mac 8GB
    - Licence Apache 2.0 (liberté totale)
    - Bon compromis qualité/ressources

Alternative similaire:
    - dots.ocr (Score: 79.1, 3B, Apache 2.0)

Auteur: CASS Project
Date: Janvier 2026
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

# Modèle DeepSeek-OCR-2 sur HuggingFace
DEEPSEEK_MODEL = "deepseek-ai/DeepSeek-OCR-2"
DEEPSEEK_MODEL_ALT = "deepseek-ai/deepseek-ocr-2-3b"  # Alternative si renommé


def check_dependencies():
    """Vérifie que les dépendances sont installées."""
    required = ["mlx", "mlx_lm", "huggingface_hub", "transformers"]
    missing = []

    for package in required:
        try:
            __import__(package.replace("-", "_"))
        except ImportError:
            missing.append(package)

    if missing:
        print(f"Dependances manquantes: {', '.join(missing)}")
        print(f"   Installez avec: pip install {' '.join(missing)}")
        sys.exit(1)

    # Vérifier mlx-vlm spécifiquement
    try:
        import mlx_vlm
    except ImportError:
        print("mlx-vlm non installe")
        print("   Installez avec: pip install mlx-vlm")
        sys.exit(1)

    print("Toutes les dependances sont installees")


def check_system_ram():
    """Vérifie que le système a assez de RAM."""
    try:
        import psutil
        ram_gb = psutil.virtual_memory().total / (1024**3)
        print(f"RAM systeme: {ram_gb:.1f} GB")

        if ram_gb < 8:
            print("ATTENTION: DeepSeek-OCR-2 necessite 8GB+ de RAM")
            response = input("Continuer quand meme? [y/N] ")
            if response.lower() != 'y':
                sys.exit(0)

        return ram_gb
    except ImportError:
        print("psutil non installe, verification RAM ignoree")
        return None


def get_model_info(model_name: str) -> dict:
    """Récupère les informations du modèle depuis HuggingFace."""
    from huggingface_hub import model_info

    try:
        info = model_info(model_name)
        return {
            "id": info.id,
            "author": info.author,
            "downloads": info.downloads,
            "likes": info.likes,
            "tags": info.tags,
            "pipeline_tag": info.pipeline_tag,
        }
    except Exception as e:
        print(f"Impossible de recuperer les infos du modele: {e}")
        return {}


def download_model(model_name: str, cache_dir: Optional[str] = None) -> str:
    """Télécharge le modèle depuis HuggingFace."""
    from huggingface_hub import snapshot_download

    print(f"Telechargement de {model_name}...")
    print("   (Cela devrait prendre 5-10 minutes)")
    start_time = time.time()

    # Patterns de fichiers à télécharger
    allow_patterns = [
        "*.json",
        "*.safetensors",
        "*.bin",
        "*.py",
        "tokenizer.*",
        "*.tiktoken",
        "*.txt",
        "*.model",
    ]

    # Exclure les gros fichiers inutiles
    ignore_patterns = [
        "*.ot",
        "*.msgpack",
        "*.h5",
        "optimizer.*",
        "training_args.*",
    ]

    model_path = snapshot_download(
        repo_id=model_name,
        allow_patterns=allow_patterns,
        ignore_patterns=ignore_patterns,
        cache_dir=cache_dir,
        resume_download=True,
    )

    elapsed = time.time() - start_time
    print(f"Telechargement termine en {elapsed:.1f}s")
    print(f"   Chemin: {model_path}")

    return model_path


def convert_to_mlx(
    model_path: str,
    output_dir: str,
    quantize: bool = True,
    q_bits: int = 4,
    q_group_size: int = 64,
) -> bool:
    """
    Convertit le modèle vers le format MLX.

    Utilise mlx-vlm pour la conversion des modèles vision-language.
    """
    print(f"Conversion vers MLX ({q_bits}-bit)...")
    print("   (Cela devrait prendre 2-5 minutes)")
    start_time = time.time()

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    try:
        # Méthode 1: Utiliser mlx_vlm.convert si disponible
        try:
            from mlx_vlm.convert import convert

            convert(
                hf_path=model_path,
                mlx_path=str(output_path),
                quantize=quantize,
                q_bits=q_bits,
                q_group_size=q_group_size,
            )

        except ImportError:
            # Méthode 2: Utiliser la ligne de commande
            print("   Utilisation de la conversion CLI...")

            cmd = [
                sys.executable, "-m", "mlx_vlm.convert",
                "--hf-path", model_path,
                "--mlx-path", str(output_path),
            ]

            if quantize:
                cmd.extend(["--quantize", "--q-bits", str(q_bits)])

            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode != 0:
                print(f"Erreur de conversion: {result.stderr}")
                return False

        elapsed = time.time() - start_time
        print(f"Conversion terminee en {elapsed:.1f}s")

        return True

    except Exception as e:
        print(f"Erreur lors de la conversion: {e}")
        import traceback
        traceback.print_exc()
        return False


def create_cass_config(
    output_dir: str,
    model_name: str,
    q_bits: int,
    q_group_size: int,
):
    """Crée le fichier de configuration CASS."""
    output_path = Path(output_dir)

    config = {
        "model_type": "deepseek_ocr",
        "original_model": model_name,
        "cass_model_level": "deepseekOCR",
        "benchmark_score": 75.4,
        "benchmark_source": "olmOCR-bench (Janvier 2026)",
        "quantization": {
            "bits": q_bits,
            "group_size": q_group_size,
        },
        "requirements": {
            "min_ram_gb": 8,
            "estimated_vram_gb": 2.5 if q_bits == 4 else 5,
        },
        "capabilities": {
            "handwriting": True,
            "historical_documents": False,
            "forms_checkboxes": False,
            "bounding_boxes": False,
            "languages": "multi",
            "output_formats": ["text", "markdown"],
        },
        "license": {
            "type": "Apache-2.0",
            "commercial_use": True,
            "educational_use": True,
            "research_use": True,
        },
        "conversion_info": {
            "tool": "convert_deepseek_ocr_mlx.py",
            "date": time.strftime("%Y-%m-%d %H:%M:%S"),
            "mlx_vlm_version": get_package_version("mlx-vlm"),
        },
    }

    config_path = output_path / "cass_config.json"
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)

    print(f"Configuration CASS sauvegardee: {config_path}")


def get_package_version(package_name: str) -> str:
    """Récupère la version d'un package."""
    try:
        import importlib.metadata
        return importlib.metadata.version(package_name.replace("_", "-"))
    except:
        return "unknown"


def verify_conversion(output_dir: str) -> bool:
    """Vérifie que la conversion a réussi."""
    output_path = Path(output_dir)

    # Vérifier les fichiers de poids
    weight_files = list(output_path.glob("*.safetensors")) + list(output_path.glob("*.npz"))

    if not weight_files:
        print("Aucun fichier de poids trouve")
        return False

    # Vérifier config.json
    config_path = output_path / "config.json"
    if not config_path.exists():
        print("config.json manquant")
        return False

    # Calculer la taille totale
    total_size = sum(f.stat().st_size for f in output_path.glob("**/*") if f.is_file())

    print(f"Verification reussie")
    print(f"   Fichiers de poids: {len(weight_files)}")
    print(f"   Taille totale: {total_size / 1e9:.2f} GB")

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Convertit DeepSeek-OCR-2 (3B) vers le format MLX pour CASS",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemples:
  # Conversion standard (4-bit, installation CASS)
  python convert_deepseek_ocr_mlx.py

  # Conversion vers répertoire spécifique
  python convert_deepseek_ocr_mlx.py --output ./deepseek-ocr-mlx-4bit

  # Conversion 8-bit (meilleure qualité)
  python convert_deepseek_ocr_mlx.py --bits 8 --output ./deepseek-ocr-mlx-8bit

Benchmark DeepSeek-OCR-2 (olmOCR-bench Janvier 2026):
  - Score manuscrit: 75.4
  - Taille: 3B params
  - RAM: ~2.5GB (4-bit) | ~5GB (8-bit)
  - Mac minimum: 8GB RAM
  - Licence: Apache 2.0 (usage libre)

Alternatives similaires (3B, Apache 2.0):
  - dots.ocr: Score 79.1
        """
    )

    # Répertoire CASS par défaut
    default_output = str(Path.home() / "Library" / "Application Support" / "CASS" / "Models" / "deepseek-ocr-mlx")

    parser.add_argument(
        "--model",
        default=DEEPSEEK_MODEL,
        help=f"Modele HuggingFace (default: {DEEPSEEK_MODEL})"
    )
    parser.add_argument(
        "--output",
        default=default_output,
        help="Repertoire de sortie (default: ~/Library/Application Support/CASS/Models/deepseek-ocr-mlx)"
    )
    parser.add_argument(
        "--bits",
        type=int,
        default=4,
        choices=[4, 8],
        help="Bits de quantization (default: 4)"
    )
    parser.add_argument(
        "--group-size",
        type=int,
        default=64,
        help="Taille des groupes de quantization (default: 64)"
    )
    parser.add_argument(
        "--no-quantize",
        action="store_true",
        help="Desactiver la quantization (poids complets)"
    )
    parser.add_argument(
        "--skip-verify",
        action="store_true",
        help="Ne pas verifier la conversion"
    )
    parser.add_argument(
        "--cache-dir",
        default=None,
        help="Repertoire de cache HuggingFace"
    )

    args = parser.parse_args()

    print("=" * 60)
    print("CASS - DeepSeek-OCR-2 MLX Converter")
    print("=" * 60)
    print(f"   Modele source:  {args.model}")
    print(f"   Destination:    {args.output}")
    print(f"   Quantization:   {'Non' if args.no_quantize else f'{args.bits}-bit'}")
    print(f"   Score manuscrit: 75.4 (olmOCR-bench)")
    print(f"   Licence:        Apache 2.0 (usage libre)")
    print("=" * 60)

    # 1. Vérifier les dépendances
    check_dependencies()

    # 2. Vérifier la RAM
    check_system_ram()

    # 3. Infos du modèle
    info = get_model_info(args.model)
    if info:
        print(f"Modele: {info.get('id', args.model)}")
        print(f"   Downloads: {info.get('downloads', 'N/A')}")

    # 4. Télécharger
    model_path = download_model(args.model, args.cache_dir)

    # 5. Convertir
    success = convert_to_mlx(
        model_path=model_path,
        output_dir=args.output,
        quantize=not args.no_quantize,
        q_bits=args.bits,
        q_group_size=args.group_size,
    )

    if not success:
        print("Conversion echouee")
        sys.exit(1)

    # 6. Créer config CASS
    create_cass_config(
        output_dir=args.output,
        model_name=args.model,
        q_bits=args.bits,
        q_group_size=args.group_size,
    )

    # 7. Vérifier
    if not args.skip_verify:
        if not verify_conversion(args.output):
            print("Verification echouee")
            sys.exit(1)

    print()
    print("=" * 60)
    print("Conversion terminee avec succes!")
    print("=" * 60)
    print(f"   Modele MLX: {args.output}")
    print()
    print("   Le modele est pret a etre utilise par CASS.")
    print("   Lancez CASS et selectionnez 'DeepSeek-OCR-2 MLX' dans les parametres.")
    print("=" * 60)


if __name__ == "__main__":
    main()
