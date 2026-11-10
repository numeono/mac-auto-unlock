"""Non-destructive protocol checks; run before owner enrollment."""
import importlib.machinery
import json
import pathlib
import socket

root = pathlib.Path(__file__).resolve().parents[1]
client = importlib.machinery.SourceFileLoader('session_client', str(root / 'mac-session')).load_module()
before = client.request({'command': 'status'})
assert before['ok'] and not before['enabled'] and not before['credential_saved'], 'Run only before enrollment'
assert before['eligible_session']
for cmd in ['begin', 'test-cycle', 'anything-else']:
    response = client.request({'command': cmd})
    assert response['ok'] is False, (cmd, response)
for payload in [b'{"command":\n', b'x' * 5000 + b'\n', b'[]\n']:
    with socket.socket(socket.AF_UNIX) as conn:
        conn.settimeout(5)
        conn.connect(str(pathlib.Path.home() / 'Library/Application Support/MacSessionHelper/control.sock'))
        conn.sendall(payload)
        data = conn.recv(4096)
        assert json.loads(data)['ok'] is False
after = client.request({'command': 'status'})
for key in ['enabled', 'credential_saved', 'locked', 'active_tasks', 'helper_unlocked_desktop', 'attempt_blocked']:
    assert before[key] == after[key], (key, before[key], after[key])
assert not after['supports_cold_boot_unlock'] and not after['supports_automatic_login']
print('PASS: disabled helper rejects unlock/test/malformed/oversized requests without changing lock state')
