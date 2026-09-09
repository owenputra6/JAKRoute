r"""Copy this package into an existing Flutter project; back up every conflict.

Usage: python scripts/install_into_flutter.py C:\path\to\flutter_project
Does not overwrite main.dart, replace pubspec.yaml, install SDKs or run Flutter.
"""
import argparse
import shutil
import time
from pathlib import Path
import xml.etree.ElementTree as ET

def install(source,target):
    if not (target/'pubspec.yaml').is_file(): raise SystemExit('Target harus root project Flutter yang memiliki pubspec.yaml.')
    stamp=time.strftime('%Y%m%d-%H%M%S')
    backup=target/'jakroute_backup'/stamp
    count=0
    def write(src,dst):
        nonlocal count
        data=src.read_bytes()
        if dst.exists() and dst.read_bytes()==data: return
        if dst.exists():
            old=backup/dst.relative_to(target)
            old.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(dst,old)
        dst.parent.mkdir(parents=True,exist_ok=True)
        dst.write_bytes(data);count+=1
    for directory in ('backend','lib','notebooks','scripts','integration'):
        for src in (source/directory).rglob('*'):
            if not src.is_file() or any(x in src.parts for x in ('__pycache__','.pytest_cache','.venv','runtime')): continue
            if src.name=='.env': continue
            relative=src.relative_to(source)
            # The host application's entry point belongs to the user's Flutter
            # project. JAKRoute uses main_jakroute_demo.dart instead.
            if relative == Path('lib')/'main.dart': continue
            write(src,target/relative)
    for src in (source/'docs').rglob('*'):
        if src.is_file(): write(src,target/'docs'/'jakroute'/src.relative_to(source/'docs'))
    write(source/'README.md',target/'JAKROUTE_README.md')
    for src in (source/'integration'/'flutter_tests').glob('*.dart'):
        write(src,target/'test'/'jakroute'/src.name)
    # Android Internet permission is needed for release; HTTP is enabled only in debug.
    ns='http://schemas.android.com/apk/res/android';ET.register_namespace('android',ns)
    for variant in ('main','debug'):
        path=target/'android'/'app'/'src'/variant/'AndroidManifest.xml'
        if variant=='main' and not path.exists(): continue
        if path.exists():
            tree=ET.parse(path);root=tree.getroot()
        else: root=ET.Element('manifest');tree=ET.ElementTree(root)
        before=ET.tostring(root)
        if not any(x.get('{'+ns+'}name')=='android.permission.INTERNET' for x in root.findall('uses-permission')):
            ET.SubElement(root,'uses-permission',{'{'+ns+'}name':'android.permission.INTERNET'})
        if variant=='debug':
            app=root.find('application')
            if app is None: app=ET.SubElement(root,'application')
            app.set('{'+ns+'}usesCleartextTraffic','true')
        if ET.tostring(root)!=before:
            if path.exists():
                old=backup/path.relative_to(target);old.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,old)
            path.parent.mkdir(parents=True,exist_ok=True);ET.indent(tree);tree.write(path,encoding='utf-8',xml_declaration=True)
    print(f'{count} files copied. Existing conflicts backed up under {backup}.')
    print('Next, from the Flutter project: flutter pub add http; flutter pub add maplibre_gl:0.26.2')
    print('Backend setup: scripts/jakroute_setup.ps1; then scripts/jakroute_run.ps1')
    print('Flutter: flutter run -t lib/main_jakroute_demo.dart --dart-define=BACKEND_URL=http://10.0.2.2:8000')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('flutter_project',type=Path)
    args=parser.parse_args()
    install(Path(__file__).resolve().parents[1],args.flutter_project.resolve())
