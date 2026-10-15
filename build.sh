#!/bin/bash
# build.sh - Script de build para InstitutionalApp iOS
# Requiere: Xcode 15+, Swift 5.9, Apple Developer Enterprise ($299/año) o cuenta Ad Hoc

set -e

PROJECT_NAME="InstitutionalApp"
SCHEME="InstitutionalApp"
CONFIGURATION="Release"
BUILD_DIR="build"
ARCHIVE_PATH="build/${PROJECT_NAME}.xcarchive"
EXPORT_PATH="build/export"
EXPORT_OPTIONS_PLIST="ExportOptions.plist"

echo "=== Building ${PROJECT_NAME} ==="

# Limpia builds previos
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Resuelve dependencias (Swift Package Manager)
echo "Resolviendo dependencias..."
xcodebuild -resolvePackageDependencies -scheme "${SCHEME}" -configuration "${CONFIGURATION}"

# Build para testing (simulador)
echo "Building para simulador..."
xcodebuild build \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "platform=iOS Simulator,name=iPhone 15" \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -quiet

# Archive para distribución
echo "Creating archive..."
xcodebuild archive \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates

# Export IPA (requiere ExportOptions.plist configurado)
if [ -f "${EXPORT_OPTIONS_PLIST}" ]; then
    echo "Exporting IPA..."
    xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_PATH}" \
        -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
        -allowProvisioningUpdates
    
    echo "✅ Build completado. IPA en: ${EXPORT_PATH}"
else
    echo "⚠️  No se encontró ExportOptions.plist. Solo archive generado en: ${ARCHIVE_PATH}"
    echo "   Crea ExportOptions.plist con teamID, method (enterprise/ad-hoc), provisioningProfiles"
fi

echo "=== Done ==="