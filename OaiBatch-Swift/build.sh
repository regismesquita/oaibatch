#!/bin/bash
#
# Build script for OaiBatch Swift app
# Regenerates app icons and builds the app using xcodebuild
#

set -e

# Configuration
APP_NAME="OaiBatch"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
PROJECT_FILE="$PROJECT_DIR/OaiBatch.xcodeproj"
SCHEME="OaiBatch"
SOURCE_ICON="$PROJECT_DIR/OaiBatch/Resources/icon.png"
APPICONSET_DIR="$PROJECT_DIR/OaiBatch/Resources/Assets.xcassets/AppIcon.appiconset"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_NAME="$APP_NAME.dmg"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

print_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Function to generate app icons from source
generate_icons() {
    print_step "Generating app icons from source..."

    if [ ! -f "$SOURCE_ICON" ]; then
        print_error "Source icon not found at: $SOURCE_ICON"
        exit 1
    fi

    # Ensure the appiconset directory exists
    mkdir -p "$APPICONSET_DIR"

    # Standard macOS icon sizes
    # Size format: actual_pixels filename_size
    declare -a ICON_SIZES=(
        "16 16x16"
        "32 16x16@2x"
        "32 32x32"
        "64 32x32@2x"
        "128 128x128"
        "256 128x128@2x"
        "256 256x256"
        "512 256x256@2x"
        "512 512x512"
        "1024 512x512@2x"
    )

    for entry in "${ICON_SIZES[@]}"; do
        read -r size name <<< "$entry"
        output_file="$APPICONSET_DIR/icon_${name}.png"
        echo "  Creating ${name} (${size}x${size} pixels)..."
        sips -z "$size" "$size" "$SOURCE_ICON" --out "$output_file" > /dev/null 2>&1
    done

    print_step "App icons generated successfully!"
}

# Function to build the app
build_app() {
    local config="${1:-Release}"

    print_step "Building $APP_NAME ($config)..."

    # Clean build directory
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
    fi
    mkdir -p "$BUILD_DIR"

    # Build the app
    xcodebuild -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$config" \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        build

    # Find the built app
    APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "*.app" -type d | head -1)

    if [ -z "$APP_PATH" ]; then
        print_error "Build failed - app bundle not found"
        exit 1
    fi

    # Copy to export directory
    mkdir -p "$EXPORT_PATH"
    cp -R "$APP_PATH" "$EXPORT_PATH/"

    print_step "Build successful! App located at: $EXPORT_PATH/$APP_NAME.app"
}

# Function to create a DMG
create_dmg() {
    print_step "Creating DMG..."

    local app_path="$EXPORT_PATH/$APP_NAME.app"

    if [ ! -d "$app_path" ]; then
        print_error "App bundle not found at: $app_path"
        print_error "Please run 'build.sh build' first"
        exit 1
    fi

    # Create DMG staging directory
    local dmg_staging="$BUILD_DIR/dmg_staging"
    rm -rf "$dmg_staging"
    mkdir -p "$dmg_staging"

    # Copy app to staging
    cp -R "$app_path" "$dmg_staging/"

    # Create Applications symlink
    ln -s /Applications "$dmg_staging/Applications"

    # Remove existing DMG
    local dmg_path="$PROJECT_DIR/$DMG_NAME"
    rm -f "$dmg_path"

    # Create DMG
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$dmg_staging" \
        -ov \
        -format UDZO \
        "$dmg_path"

    print_step "DMG created at: $dmg_path"
}

# Function to clean build artifacts
clean() {
    print_step "Cleaning build artifacts..."
    rm -rf "$BUILD_DIR"
    rm -f "$PROJECT_DIR/$DMG_NAME"
    print_step "Clean complete!"
}

# Show usage
usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  icons       Generate app icons from source image"
    echo "  build       Build the app (Release configuration)"
    echo "  build-debug Build the app (Debug configuration)"
    echo "  dmg         Create a DMG installer"
    echo "  all         Generate icons, build, and create DMG"
    echo "  clean       Remove build artifacts"
    echo "  help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 all          # Full build with DMG"
    echo "  $0 icons build  # Regenerate icons and build"
}

# Main entry point
main() {
    cd "$PROJECT_DIR"

    if [ $# -eq 0 ]; then
        usage
        exit 0
    fi

    for cmd in "$@"; do
        case "$cmd" in
            icons)
                generate_icons
                ;;
            build)
                build_app "Release"
                ;;
            build-debug)
                build_app "Debug"
                ;;
            dmg)
                create_dmg
                ;;
            all)
                generate_icons
                build_app "Release"
                create_dmg
                ;;
            clean)
                clean
                ;;
            help|--help|-h)
                usage
                ;;
            *)
                print_error "Unknown command: $cmd"
                usage
                exit 1
                ;;
        esac
    done
}

main "$@"
