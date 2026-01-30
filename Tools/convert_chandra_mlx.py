#!/usr/bin/env python3
"""
convert_chandra_mlx.py

Convertit le modèle Chandra (Datalab) vers le format MLX avec quantization.

Chandra est le meilleur modèle OCR manuscrit disponible (Score: 83.1 sur olmOCR-bench).
Optimisé pour les lettres manuscrites, formulaires, et documents historiques.

Usage:
    python convert_chandra_mlx.py --output ~/Library/Application\ Support/CASS/Models/chandra-mlx
    python convert_chandra_mlx.py --bits 8 --output ./chandra-mlx-8bit

Prérequis:
    pip install mlx-lm mlx-vlm huggingface_hub transformers torch

Spécifications Chandra:
    - Taille: 9B params
    - Score olmOCR-bench: 83.1 (manuscrit)
    - RAM requise: ~6GB (4-bit) | ~12GB (8-bit)
    - Mac minimum: 16GB RAM
    - Licence: OpenRAIL-M (OK pour usage éducatif non-commercial)
    - Source: https://huggingface.co/datalab-to/Chandra

Points forts:
    - Meilleur score sur écriture manuscrite
    - Testé sur lettres historiques (Ramanujan 1913)
    - Bounding boxes natives (HTML output)
    - 40+ langues supportées
    - Output Markdown/HTML/JSON

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

# Modèle Chandra sur HuggingFace
CHANDRA_MODEL = "datalab-to/Chandra"
CHANDRA_MODEL_ALT = "datalab-to/Chandra-VL-9B"  # Alternative si renommé


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

        if ram_gb < 16:
            print("ATTENTION: Chandra (9B) necessite 16GB+ de RAM")
            print("   Considerez DeepSeek-OCR-2 (3B) pour les machines 8GB")
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
    print("   (Cela peut prendre 10-30 minutes selon votre connexion)")
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
    print("   (Cela peut prendre 5-15 minutes)")
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
        "model_type": "chandra",
        "original_model": model_name,
        "cass_model_level": "chandra",
        "benchmark_score": 83.1,
        "benchmark_source": "olmOCR-bench (Janvier 2026)",
        "quantization": {
            "bits": q_bits,
            "group_size": q_group_size,
        },
        "requirements": {
            "min_ram_gb": 16,
            "estimated_vram_gb": 6 if q_bits == 4 else 12,
        },
        "capabilities": {
            "handwriting": True,
            "historical_documents": True,
            "forms_checkboxes": True,
            "bounding_boxes": True,
            "languages": "40+",
            "output_formats": ["markdown", "html", "json"],
        },
        "license": {
            "type": "OpenRAIL-M",
            "commercial_use": "restricted",
            "educational_use": True,
            "research_use": True,
        },
        "conversion_info": {
            "tool": "convert_chandra_mlx.py",
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


def install_to_cass(output_dir: str):
    """Installe le modèle dans le répertoire CASS."""
    cass_models_dir = Path.home() / "Library" / "Application Support" / "CASS" / "Models"
    target_dir = cass_models_dir / "chandra-mlx"

    if str(Path(output_dir).resolve()) == str(target_dir.resolve()):
        print("Modele deja dans le repertoire CASS")
        return

    print(f"Installation vers {target_dir}...")

    # Créer le répertoire parent si nécessaire
    cass_models_dir.mkdir(parents=True, exist_ok=True)

    # Copier ou déplacer
    import shutil
    if target_dir.exists():
        print("   Suppression de l'ancienne version...")
        shutil.rmtree(target_dir)

    shutil.copytree(output_dir, target_dir)
    print(f"Installe dans: {target_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Convertit Chandra (9B) vers le format MLX pour CASS",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemples:
  # Conversion standard (4-bit, installation CASS)
  python convert_chandra_mlx.py

  # Conversion vers répertoire spécifique
  python convert_chandra_mlx.py --output ./chandra-mlx-4bit

  # Conversion 8-bit (meilleure qualité, plus de RAM)
  python convert_chandra_mlx.py --bits 8 --output ./chandra-mlx-8bit

  # Sans quantization (poids complets, ~18GB)
  python convert_chandra_mlx.py --no-quantize --output ./chandra-mlx-full

Benchmark Chandra (olmOCR-bench Janvier 2026):
  - Score manuscrit: 83.1 (meilleur disponible)
  - Taille: 9B params
  - RAM: ~6GB (4-bit) | ~12GB (8-bit) | ~18GB (full)
        """
    )

    # Répertoire CASS par défaut
    default_output = str(Path.home() / "Library" / "Application Support" / "CASS" / "Models" / "chandra-mlx")

    parser.add_argument(
        "--model",
        default=CHANDRA_MODEL,
        help=f"Modele HuggingFace (default: {CHANDRA_MODEL})"
    )
    parser.add_argument(
        "--output",
        default=default_output,
        help="Repertoire de sortie (default: ~/Library/Application Support/CASS/Models/chandra-mlx)"
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
    print("CASS - Chandra MLX Converter")
    print("=" * 60)
    print(f"   Modele source:  {args.model}")
    print(f"   Destination:    {args.output}")
    print(f"   Quantization:   {'Non' if args.no_quantize else f'{args.bits}-bit'}")
    print(f"   Score manuscrit: 83.1 (olmOCR-bench)")
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
    print("   Lancez CASS et selectionnez 'Chandra MLX' dans les parametres.")
    print("=" * 60)


if __name__ == "__main__":
    main()
