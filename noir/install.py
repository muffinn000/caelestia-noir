#!/usr/bin/env python3
"""Install the NOIR profile over an existing Caelestia setup, with backup."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import tomllib

PROFILE = Path(__file__).resolve().parent

def planned_files(home):
    files = {}
    for source_dir, destination_dir in [('config', '.config'), ('data', '.local/share'), ('bin', '.local/bin')]:
        for source in (PROFILE/source_dir).rglob('*'):
            if source.is_file():
                files[Path(destination_dir)/source.relative_to(PROFILE/source_dir)] = source
    state = Path('.local/state/caelestia')
    wallpaper = home/'.local/share/caelestia/noir/Noir-Orbit.png'
    palette = json.loads((PROFILE/'data/caelestia/noir/palette.json').read_text())
    files[state/'scheme.json'] = json.dumps(palette,indent=2)+'\n'
    files[state/'wallpaper/path.txt'] = str(wallpaper)
    files[state/'wallpaper/current'] = ('symlink', str(wallpaper))
    files[state/'wallpaper/thumbnail.jpg'] = ('symlink', str(wallpaper))
    def osc(value, *indices):
        return '\x1b]'+ ';'.join(map(str,indices)) + ';rgb:' + '/'.join(value[i:i+2] for i in (0,2,4)) + '\x1b\\'
    colours=palette['colours']
    sequences=osc(colours['onSurface'],10)+osc(colours['surface'],11)+osc('ffffff',12)+osc('777777',17)
    sequences+=''.join(osc(colours[f'term{i}'],4,i) for i in range(16))
    sequences+=''.join(osc(colours[key],4,i) for i,key in enumerate(['primary','secondary','tertiary'],16))
    files[state/'sequences.txt']=sequences
    return files

def validate():
    for path in (PROFILE/'config').rglob('*.json'):
        json.loads(path.read_text())
    tomllib.loads((PROFILE/'config/starship.toml').read_text())
    palette=json.loads((PROFILE/'data/caelestia/noir/palette.json').read_text())
    assert all(len(v)==6 and v[:2]==v[2:4]==v[4:6] for v in palette['colours'].values())
    assert 'WlrLayershell.layer: WlrLayer.Overlay' in (PROFILE/'config/quickshell/purple/shell.qml').read_text()

def install(home, dry_run=False):
    validate()
    files=planned_files(home)
    if dry_run:
        print('\n'.join(str(home/path) for path in sorted(files)))
        print(f'Would install {len(files)} files. No changes made.')
        return None
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    backup=home/'.local/state/noir/backups'/stamp
    backup.mkdir(parents=True,mode=0o700)
    manifest=[]
    # Save every original before making any changes.
    for rel in sorted(files):
        target=home/rel
        if target.exists() and target.is_dir() and not target.is_symlink():
            raise IsADirectoryError(target)
        exists=target.exists() or target.is_symlink()
        manifest.append({'path':str(rel),'existed':exists})
        if exists:
            saved=backup/'files'/rel
            saved.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(target,saved,follow_symlinks=False)
    (backup/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    for rel,source in files.items():
        target=home/rel
        target.parent.mkdir(parents=True,exist_ok=True)
        target.unlink(missing_ok=True)
        if isinstance(source,Path):
            shutil.copy2(source,target)
        elif isinstance(source,tuple):
            target.symlink_to(source[1])
        else:
            target.write_text(source)
    # Never install or overwrite a user's task list or running timer.
    (home/'.local/state/purple-desktop').mkdir(parents=True,exist_ok=True)
    print(f'Installed {len(files)} NOIR files. Backup: {backup}')
    print('Log out and back in to start the panel, or run ~/.local/bin/noir-panel and hyprctl reload config-only.')
    return backup

def restore(home, backup):
    entries=json.loads((backup/'manifest.json').read_text())
    for entry in entries:
        rel=Path(entry['path'])
        if rel.is_absolute() or '..' in rel.parts:
            raise ValueError(f'Invalid backup path: {rel}')
        saved=backup/'files'/rel
        if entry['existed'] and not (saved.exists() or saved.is_symlink()):
            raise FileNotFoundError(saved)
        target=home/rel
        if target.exists() and target.is_dir() and not target.is_symlink():
            raise IsADirectoryError(target)
    for entry in entries:
        target=home/entry['path']
        target.unlink(missing_ok=True)
        if entry['existed']:
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(backup/'files'/entry['path'],target,follow_symlinks=False)
    print('Previous configuration restored. Log out and back in to restart the original panel.')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run',action='store_true',help='List destinations without changing files')
    parser.add_argument('--check',action='store_true',help='Validate profile files without installing')
    parser.add_argument('--target-home',type=Path,default=Path.home(),help='Target home directory; useful for offline checks')
    parser.add_argument('--restore',type=Path,metavar='BACKUP',help='Restore a backup made by this installer')
    args=parser.parse_args()
    home=args.target_home.expanduser().resolve()
    if args.check:
        validate();print('NOIR profile is valid.')
    elif args.restore:
        restore(home,args.restore.expanduser().resolve())
    else:
        install(home,args.dry_run)
