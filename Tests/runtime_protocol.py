"""Installed-helper checks: malformed requests and status only, no valid unlock."""
import importlib.util
import importlib.machinery
import json
from pathlib import Path
import socket
import time

root = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('session_client', str(root / 'mac-session'))
spec = importlib.util.spec_from_loader(loader.name, loader)
client = importlib.util.module_from_spec(spec)
loader.exec_module(client)
before = client.request({'command': 'status'})
assert before.get('ok'), before
sock = str(Path.home() / 'Library/Application Support/MacSessionHelper/control.sock')
for payload in [b'{"command":\n', b'x' * 5000 + b'\n', b'[]\n',
                b'{"command":"status","unexpected":true}\n',
                b'{"command":"begin","seconds":"60"}\n',
                b'{"command":"begin","seconds":true}\n']:
    with socket.socket(socket.AF_UNIX) as conn:
        conn.settimeout(5)
        conn.connect(sock)
        conn.sendall(payload)
        response = json.loads(conn.recv(4096))
        if response.get('ok') and response.get('lease'):
            client.request({'command': 'end', 'lease': response['lease']})
        assert response.get('ok') is False, 'Malformed request was accepted'

with socket.socket(socket.AF_UNIX) as conn:
    conn.settimeout(5)
    conn.connect(sock)
    started = time.monotonic()
    for _ in range(10):
        try:
            conn.sendall(b' ')
        except (BrokenPipeError, ConnectionResetError):
            break
        time.sleep(0.4)
    try:
        output = conn.recv(4096)
        if output:
            assert json.loads(output)['ok'] is False
    except ConnectionResetError:
        pass
    elapsed = time.monotonic() - started
    assert elapsed < 5, f'Total read deadline was not enforced: {elapsed}'

after = client.request({'command': 'status'})
assert after.get('ok'), after
for key in ['enabled', 'credential_saved', 'active_tasks', 'attempt_blocked']:
    assert before[key] == after[key], f'Unexpected state change: {key}'
print(f'PASS: malformed requests rejected, slow client closed in {elapsed:.1f}s, command server responsive, task/credential state unchanged')
