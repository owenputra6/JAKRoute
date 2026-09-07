import json
import pytest
from pathlib import Path
from jakroute.indoor_routing import IndoorRouter

DATA=Path(__file__).resolve().parents[1]/'data'
@pytest.fixture(scope='session')
def site(): return json.loads((DATA/'station_demo.json').read_text())
@pytest.fixture(scope='session')
def router(site): return IndoorRouter(site)
@pytest.fixture
def users(): return json.loads((DATA/'crowd_users.json').read_text())['users']
@pytest.fixture
def incidents(): return json.loads((DATA/'forum_summary_seed.json').read_text())['incidents']
