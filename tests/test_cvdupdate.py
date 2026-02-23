import json
import datetime
from pathlib import Path

from tests.fixtures.revert import revert_homedir

from cvdupdate.cvdupdate import CVDUpdate

def test_instantiation(revert_homedir):
    c = CVDUpdate()

def test_alternate_config_locations(revert_homedir, tmp_path):
    ''' Test that we can save config and state files to alternative locations '''
    # ensure we're starting with a clean slate
    default_cvdupdate_dir = Path.home() / '.cvdupdate'
    assert not default_cvdupdate_dir.exists()

    # set config and state to be in pytests's /tmp/pytest-*
    config_file_path = tmp_path / 'config.json'
    state_file_path = tmp_path / 'state.json'
    c = CVDUpdate(
        config=config_file_path,
        state_file=str(state_file_path),
    )

    # verify config file is created and matches in-memory config
    assert config_file_path.exists()
    assert json.loads(config_file_path.read_text()) == c.config
    expected_config = {**c.default_config, 'state_file': str(state_file_path)}
    assert c.config == expected_config

    # verify state file is created and has the three default databases
    assert state_file_path.exists()
    state_file_json = json.loads(state_file_path.read_text())
    assert state_file_json == c.state
    assert set(state_file_json['dbs'].keys()) == {'main.cvd', 'daily.cvd', 'bytecode.cvd'}
    del c.state['uuid']
    assert c.state == c.default_state

    # logs are disabled by default, so ~/.cvdupdate should not be created at all
    assert not default_cvdupdate_dir.exists()


def test_logs_enabled(revert_homedir, tmp_path):
    ''' Test that when logs_enabled=True, a dated log file is created in the logs directory '''
    logs_dir_path = tmp_path / 'logs'
    CVDUpdate(
        config=tmp_path / 'config.json',
        state_file=str(tmp_path / 'state.json'),
        logs_enabled=True,
        logs_directory=str(logs_dir_path),
    )

    assert logs_dir_path.exists()
    log_files = list(logs_dir_path.iterdir())
    assert len(log_files) == 1
    assert log_files[0].name == f"{datetime.date.today():%Y-%m-%d}.log"


def test_default_config_not_mutated(revert_homedir, tmp_path):
    ''' default_config and default_state are both class-level attributes
    Ensure that when we copy these, we are actually copying them and not simply reassigning
    note that this typically won't be a problem in normal usage,
    but it was a problem during testing and was really annoying to track down
    '''
    a = CVDUpdate()
    config_file_path = tmp_path / 'config.json'
    # set the config file to be in pytests /tmp/pytest-*
    b = CVDUpdate(config=config_file_path)

    assert all(val == b.config[key] for key,val in a.config.items() if key != 'state_file')
    assert id(a.config) != id(b.config)
    assert id(a.default_config) == id(b.default_config) == id(CVDUpdate.default_config)
    assert id(a.state) != id(b.state)
    assert id(a.default_state) == id(b.default_state)


def test_v1_config_migrates_successfully(revert_homedir):
    ''' Test that a v1.0.x config.json is migrated to the current format on load:
    - old space-separated keys are renamed to underscore keys
    - values are preserved across the rename
    - dbs and uuid are moved out of config into a separate state.json
    - new keys absent from the old config are filled in from defaults
    - logs_enabled is set to True (old configs always had logging on)
    '''
    default_cvdupdate_dir = Path.home() / '.cvdupdate'
    default_cvdupdate_dir.mkdir(parents=True)

    logs_dir = str(default_cvdupdate_dir / 'logs')
    db_dir   = str(default_cvdupdate_dir / 'database')

    old_config = json.loads(Path('tests/files/v1.0.2.config.json').read_text())
    old_config['log directory'] = logs_dir
    old_config['db directory']  = db_dir
    with (default_cvdupdate_dir / 'config.json').open('w') as f:
        json.dump(old_config, f)

    a = CVDUpdate()

    # --- key renames: old keys must be gone ---
    old_keys = {'nameserver', 'max retry', 'log directory', 'rotate logs',
                '# logs to keep', 'db directory', 'rotate cdiffs',
                '# cdiffs to keep', 'dbs', 'uuid'}
    assert old_keys.isdisjoint(a.config.keys())

    # --- key renames: values must be preserved ---
    assert a.config['nameservers']    == old_config['nameserver']
    assert a.config['max_retries']    == old_config['max retry']
    assert a.config['logs_directory'] == logs_dir
    assert a.config['logs_rotate']    == old_config['rotate logs']
    assert a.config['logs_to_keep']   == old_config['# logs to keep']
    assert a.config['dbs_directory']  == db_dir
    assert a.config['cdiffs_rotate']  == old_config['rotate cdiffs']
    assert a.config['cdiffs_to_keep'] == old_config['# cdiffs to keep']

    # --- new keys must be filled in from defaults ---
    assert a.config['state_file'] == CVDUpdate.default_config['state_file']

    # --- config must have exactly the current key set ---
    assert a.config.keys() == CVDUpdate.default_config.keys()

    # --- old config implies logs were always on: logs_enabled must be True and log file present ---
    assert a.config['logs_enabled'] == True
    log_files = list(Path(logs_dir).iterdir())
    assert len(log_files) == 1
    assert log_files[0].name == f"{datetime.date.today():%Y-%m-%d}.log"

    # --- dbs and uuid must have been moved to state ---
    assert a.state['dbs']  == old_config['dbs']
    assert a.state['uuid'] == old_config['uuid']

    # --- verify config.json on disk matches in-memory config ---
    with (default_cvdupdate_dir / 'config.json').open() as f:
        disk_config = json.load(f)
    assert disk_config == a.config

    # --- verify state.json on disk matches in-memory state ---
    with Path(disk_config['state_file']).open() as f:
        disk_state = json.load(f)
    assert disk_state == a.state
