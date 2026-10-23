#!/usr/bin/env python3
"""Run current regressions in a temporary project with a separate save directory."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default='godot')
args = parser.parse_args()
source = Path(__file__).resolve().parents[1] / 'game'
qa_name = 'Silverwing-OpenSource-QA-' + uuid.uuid4().hex
env = dict(os.environ, SILVERWING_QA_DIR=qa_name)
with tempfile.TemporaryDirectory(prefix='silverwing-qa-') as scratch:
    project = Path(scratch) / 'game'
    shutil.copytree(source, project, ignore=shutil.ignore_patterns('.godot', 'builds', '*.import'))
    (project / 'override.cfg').write_text('[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + qa_name + '"\n')
    base = [args.godot, '--headless', '--path', str(project)]
    subprocess.run(base + ['--editor', '--import'], env=env, check=True)
    for name in ['v09-touch-startup', 'v09-skill-regression', 'v09-dodge-integration', 'v09-route-audit-regression']:
        subprocess.run(base + ['--script', 'res://qa/' + name + '.gd', '--', '--touch'], env=env, check=True)
print('All four regression scripts passed. Isolated save directory:', qa_name)
