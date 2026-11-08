#!/usr/bin/env python3
"""Write only the generated installer volume's Finder layout; no Finder automation.

Build-only dependencies: ds-store 1.3.3 and mac-alias 2.2.2.
API reference: https://ds-store.readthedocs.io/en/latest/
"""
from pathlib import Path
import sys
from ds_store import DSStore
from mac_alias import Alias

volume = Path(sys.argv[1])
if volume.parent != Path('/Volumes') or volume.name != 'LTEModemCompact':
    raise SystemExit('Expected the dedicated installer volume.')
background = volume / '.background' / 'installer.tiff'
with DSStore.open(str(volume / '.DS_Store'), 'w+') as store:
    store['.']['bwsp'] = {
        'WindowBounds': '{{180, 140}, {760, 500}}',
        'ShowToolbar': False, 'ShowStatusBar': False, 'ShowPathbar': False,
        'ShowSidebar': False, 'ContainerShowSidebar': False, 'ShowTabView': False,
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundType': 2,
        'backgroundImageAlias': Alias.for_file(str(background)).to_bytes(),
        'backgroundColorRed': 0.957, 'backgroundColorGreen': 0.969, 'backgroundColorBlue': 0.984,
        'iconSize': 80.0, 'textSize': 12.0, 'gridSpacing': 100.0,
        'gridOffsetX': 0.0, 'gridOffsetY': 0.0, 'arrangeBy': 'none',
        'labelOnBottom': True, 'showItemInfo': False, 'showIconPreview': True,
        'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
    }
    store['.']['vSrn'] = ('long', 1)
    store['.']['vstl'] = ('type', b'icnv')
    store['LTEModemCompact.app']['Iloc'] = (210, 250)
    store['Applications']['Iloc'] = (550, 250)
    store['安装说明.txt']['Iloc'] = (663, 407)
