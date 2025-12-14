#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
import customtkinter

# Configuration
APP_NAME = "OaiBatch"
MAIN_SCRIPT = "oaibatch_gui.py"
SOURCE_ICON = "assets/icon.png"
BUILD_DIR = Path("build_artifacts")
DIST_DIR = Path("dist")
DMG_NAME = "OaiBatch.dmg"

def run_command(cmd, shell=False):
    """Run a shell command and check for errors."""
    print(f"Running: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    subprocess.check_call(cmd, shell=shell)

def create_icns(source_png: str, output_path: Path):
    """Create an .icns file from a source PNG using sips and iconutil."""
    print(f"Creating icon from {source_png}...")
    
    if not os.path.exists(source_png):
        print(f"Warning: Icon source {source_png} not found. Skipping icon creation.")
        return None

    iconset_dir = BUILD_DIR / f"{APP_NAME}.iconset"
    if iconset_dir.exists():
        shutil.rmtree(iconset_dir)
    iconset_dir.mkdir(parents=True)

    # Standard sizes for macOS icons
    sizes = [16, 32, 128, 256, 512]
    
    try:
        for size in sizes:
            # Normal size
            run_command([
                "sips", "-z", str(size), str(size), 
                source_png, 
                "--out", str(iconset_dir / f"icon_{size}x{size}.png")
            ])
            # Retina size (@2x)
            run_command([
                "sips", "-z", str(size*2), str(size*2), 
                source_png, 
                "--out", str(iconset_dir / f"icon_{size}x{size}@2x.png")
            ])

        # Convert iconset to icns
        run_command(["iconutil", "-c", "icns", str(iconset_dir), "-o", str(output_path)])
        return output_path
        
    except subprocess.CalledProcessError as e:
        print(f"Error creating icon: {e}")
        return None

def build_app(icon_path: Path):
    """Run PyInstaller to build the .app bundle."""
    print("Building .app bundle...")
    
    # Get customtkinter path for add-data
    ctk_path = os.path.dirname(customtkinter.__file__)
    
    # Construct PyInstaller arguments
    cmd = [
        "pyinstaller",
        "--noconfirm",
        "--clean",
        "--windowed",
        "--name", APP_NAME,
        f"--add-data={ctk_path}:customtkinter",
        MAIN_SCRIPT
    ]
    
    if icon_path and icon_path.exists():
        cmd.append(f"--icon={str(icon_path)}")
    
    run_command(cmd)

def create_dmg():
    """Create a DMG file containing the app."""
    print("Creating DMG...")
    
    app_path = DIST_DIR / f"{APP_NAME}.app"
    if not app_path.exists():
        raise FileNotFoundError(f"App bundle not found at {app_path}")

    # Create a folder for the DMG content
    dmg_source = BUILD_DIR / "dmg_source"
    if dmg_source.exists():
        shutil.rmtree(dmg_source)
    dmg_source.mkdir(parents=True)

    # Copy the .app to the source folder
    print(f"Copying {app_path} to {dmg_source}...")
    shutil.copytree(app_path, dmg_source / f"{APP_NAME}.app")

    # Create /Applications symlink
    print("Creating /Applications symlink...")
    os.symlink("/Applications", dmg_source / "Applications")

    # Remove existing DMG if it exists
    if os.path.exists(DMG_NAME):
        os.remove(DMG_NAME)

    # Create the DMG
    cmd = [
        "hdiutil", "create",
        "-volname", APP_NAME,
        "-srcfolder", str(dmg_source),
        "-ov",
        "-format", "UDZO",
        DMG_NAME
    ]
    run_command(cmd)
    
    print(f"Success! DMG created at: {os.path.abspath(DMG_NAME)}")

def main():
    # Setup build env
    if BUILD_DIR.exists():
        shutil.rmtree(BUILD_DIR)
    BUILD_DIR.mkdir()

    # Step 1: Create Icon
    icon_path = BUILD_DIR / f"{APP_NAME}.icns"
    created_icon = create_icns(SOURCE_ICON, icon_path)
    
    # Step 2: Build App
    build_app(created_icon)
    
    # Step 3: Create DMG
    create_dmg()
    
    # Cleanup
    print("Cleaning up temporary build artifacts...")
    # shutil.rmtree(BUILD_DIR) # Optional: keep for debugging if needed
    print("Done.")

if __name__ == "__main__":
    main()
