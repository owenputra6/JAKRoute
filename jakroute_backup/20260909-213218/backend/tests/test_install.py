import importlib.util
from pathlib import Path
import xml.etree.ElementTree as ET

def test_installer_preserves_existing_app_and_pubspec(tmp_path):
    source=Path(__file__).resolve().parents[2]
    spec=importlib.util.spec_from_file_location('installer',source/'scripts'/'install_into_flutter.py')
    installer=importlib.util.module_from_spec(spec);spec.loader.exec_module(installer)
    (tmp_path/'pubspec.yaml').write_text('name: existing_app\n')
    (tmp_path/'lib').mkdir();(tmp_path/'lib'/'main.dart').write_text('// user app, preserve\n')
    manifest=tmp_path/'android'/'app'/'src'/'main'/'AndroidManifest.xml'
    manifest.parent.mkdir(parents=True)
    manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="OriginalApp" /></manifest>')
    installer.install(source,tmp_path)
    assert (tmp_path/'pubspec.yaml').read_text()=='name: existing_app\n'
    assert (tmp_path/'lib'/'main.dart').read_text()=='// user app, preserve\n'
    root=ET.parse(manifest).getroot()
    assert root.find('application').get('{http://schemas.android.com/apk/res/android}label')=='OriginalApp'
    assert root.find('uses-permission') is not None
    assert (tmp_path/'lib'/'main_jakroute_demo.dart').exists()
    assert (tmp_path/'test'/'jakroute'/'api_client_test.dart').exists()
