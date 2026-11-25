#!/bin/zsh
# Per-user installation only. Never changes TCC, Keychain ACLs or FileVault.
set -eu
cd "${0:A:h}"
[[ $EUID != 0 ]] || { print -u2 'Run as your logged-in user, without sudo.'; exit 1; }
app_root="$HOME/Applications"
cli_root="$HOME/.local/bin"
agent_root="$HOME/Library/LaunchAgents"
label=local.mads.MacSessionHelper
bundle_name='Mac Auto Unlock.app'
target="$app_root/$bundle_name"
legacy_target="$app_root/Mac Session Helper.app"
if [[ ! -e "$target" && ! -L "$target" && ( -e "$legacy_target" || -L "$legacy_target" ) ]]; then
    target="$legacy_target"
fi
plist="$agent_root/$label.plist"
if [[ -x "$cli_root/mac-session" ]]; then
    status_json=$("$cli_root/mac-session" status) || status_json='{}'
    print -r -- "$status_json" | /usr/bin/python3 -c 'import json,sys; s=json.load(sys.stdin); sys.exit(1 if s.get("active_tasks",0) or s.get("setup_open",False) else 0)' || {
        print -u2 'Finish active desktop tasks and close local setup before installing.'; exit 1;
    }
fi
for directory in "$app_root" "$cli_root" "$agent_root"; do
    [[ ! -L "$directory" ]] || { print -u2 'Refusing a symlinked installation directory.'; exit 1; }
    mkdir -p "$directory"
done
[[ ! -L "$target" && ! -L "$plist" ]] || { print -u2 'Refusing a symlinked installation target.'; exit 1; }
zsh build.sh
codesign --verify --strict "build/$bundle_name"
stage=$(mktemp -d "$app_root/.MacSessionHelper.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "build/$bundle_name" "$stage/$bundle_name"
codesign --verify --strict "$stage/$bundle_name"
backup="$HOME/Library/Application Support/MacSessionHelperBackups/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p -m 700 "$backup"
[[ ! -e "$target" ]] || ditto "$target" "$backup/${target:t}"
[[ ! -e "$plist" ]] || cp "$plist" "$backup/agent.plist"
launchctl bootout "gui/$EUID/$label" 2>/dev/null || true
# Both copies are local; the previous bundle remains available for recovery.
if [[ -e "$target" ]]; then mv "$target" "$stage/previous.app"; fi
if ! mv "$stage/$bundle_name" "$target"; then
    [[ ! -e "$stage/previous.app" ]] || mv "$stage/previous.app" "$target"
    exit 1
fi
install -m 755 mac-session "$cli_root/mac-session"
/usr/bin/python3 - "$target" "$plist" "$label" <<'PY'
import pathlib,plistlib,sys
app,output,label=sys.argv[1:]
data={'Label':label,'ProgramArguments':[app+'/Contents/MacOS/MacSessionHelper'],
      'LimitLoadToSessionType':'Aqua','RunAtLoad':True,'KeepAlive':{'SuccessfulExit':False},
      'ProcessType':'Interactive','ThrottleInterval':10,'Umask':63,
      'StandardOutPath':'/dev/null','StandardErrorPath':'/dev/null'}
p=pathlib.Path(output);p.write_bytes(plistlib.dumps(data));p.chmod(0o600)
PY
launchctl bootstrap "gui/$EUID" "$plist"
print "Installed $target"
print 'Check mac-session status. A rebuilt signing identity may require permission refresh and local password setup.'
print "Previous installation backup: $backup"
