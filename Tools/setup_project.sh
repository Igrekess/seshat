#!/bin/bash

# CASS Project Setup Script
# This script helps set up the development environment

set -e

echo "🚀 Configuration du projet CASS..."

# Check macOS version
OS_VERSION=$(sw_vers -productVersion)
echo "📱 macOS version: $OS_VERSION"

# Check for Apple Silicon
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo "⚠️  CASS nécessite Apple Silicon (M1/M2/M3/M4)"
    echo "   Architecture détectée: $ARCH"
    exit 1
fi
echo "✅ Apple Silicon détecté"

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode n'est pas installé"
    echo "   Installez Xcode depuis l'App Store"
    exit 1
fi
XCODE_VERSION=$(xcodebuild -version | head -1)
echo "✅ $XCODE_VERSION"

# Create Application Support directory for models
MODELS_DIR="$HOME/Library/Application Support/CASS/Models"
if [ ! -d "$MODELS_DIR" ]; then
    mkdir -p "$MODELS_DIR"
    echo "✅ Dossier des modèles créé: $MODELS_DIR"
else
    echo "✅ Dossier des modèles existant: $MODELS_DIR"
fi

# Resolve Swift packages
echo "📦 Résolution des dépendances Swift..."
cd "$(dirname "$0")/.."
swift package resolve

echo ""
echo "✅ Configuration terminée!"
echo ""
echo "Pour ouvrir le projet dans Xcode:"
echo "  open Package.swift"
echo ""
echo "Pour builder en ligne de commande:"
echo "  swift build"
echo ""
echo "Pour lancer les tests:"
echo "  swift test"
echo ""
