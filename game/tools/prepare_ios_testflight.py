#!/usr/bin/env python3
"""Prepare a Godot project-only iOS export for this TestFlight handoff.
Run after every Godot re-export: python3 tools/prepare_ios_testflight.py EXPORT_DIR
"""
import argparse
import json
import plistlib
import re
import xml.etree.ElementTree as ET
from pathlib import Path

BUNDLE_ID = "org.example.silverwing"
UNUSED_PERMISSIONS = ("NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription")

def prepare(export_dir):
    export_dir = Path(export_dir).resolve()
    projects = list(export_dir.glob("*.xcodeproj"))
    if len(projects) != 1:
        raise SystemExit("Expected exactly one Xcode project in the export directory")
    project = projects[0]
    pbx = project / "project.pbxproj"
    text = pbx.read_text()
    text, identities = re.subn(r'CODE_SIGN_IDENTITY = [^;]+;', 'CODE_SIGN_IDENTITY = "Apple Development";', text)
    text, identifiers = re.subn(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;', 'PRODUCT_BUNDLE_IDENTIFIER = ' + BUNDLE_ID + ';', text)
    if identities != 4 or identifiers != 2:
        raise SystemExit("Unexpected project signing layout; review manually")
    info_files = list(export_dir.glob("*/*-Info.plist"))
    options_files = list(export_dir.glob("*/export_options.plist"))
    if len(info_files) != 1 or len(options_files) != 1:
        raise SystemExit("Expected one application Info.plist and export options file")
    scheme_files = list(project.glob("xcshareddata/xcschemes/*.xcscheme"))
    if len(scheme_files) != 1:
        raise SystemExit("Expected one shared Xcode scheme")
    scheme = ET.parse(scheme_files[0])
    archive = scheme.getroot().find("ArchiveAction")
    if archive is None:
        raise SystemExit("Shared scheme has no ArchiveAction")
    archive.set("buildConfiguration", "Release")
    profile = scheme.getroot().find("ProfileAction")
    if profile is not None:
        profile.set("buildConfiguration", "Release")
    info = plistlib.loads(info_files[0].read_bytes())
    removed = [key for key in UNUSED_PERMISSIONS if key in info]
    for key in UNUSED_PERMISSIONS:
        info.pop(key, None)
    options = plistlib.loads(options_files[0].read_bytes())
    options["method"] = "app-store-connect"
    options["signingStyle"] = "automatic"
    options["uploadSymbols"] = True
    options.pop("provisioningProfiles", None)
    options.pop("signingCertificate", None)
    pbx.write_text(text)
    info_files[0].write_bytes(plistlib.dumps(info, sort_keys=False))
    options_files[0].write_bytes(plistlib.dumps(options, sort_keys=False))
    ET.indent(scheme, space="  ")
    scheme.write(scheme_files[0], encoding="utf-8", xml_declaration=True)
    summary = {"bundle_id": BUNDLE_ID, "debug_identity": "Apple Development", "release_identity": "Apple Development", "archive_configuration": "Release", "export_method": "app-store-connect", "removed_unused_permissions": removed}
    print(json.dumps(summary, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export_dir")
    prepare(parser.parse_args().export_dir)
