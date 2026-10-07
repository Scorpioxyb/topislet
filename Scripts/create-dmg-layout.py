#!/usr/bin/env python3
"""Write Finder layout metadata into an owned, mounted candidate image.

No Finder automation, app activation, user preferences, or UI input.
Install pinned build-only dependencies from dmg-layout-requirements.txt.
"""
import argparse
from pathlib import Path

from ds_store import DSStore
from mac_alias import Alias


def create_layout(volume: Path) -> None:
    app = volume / "顶屿.app"
    applications = volume / "Applications"
    background = volume / ".background/background.png"
    if not app.is_dir() or not applications.is_symlink() or applications.readlink() != Path("/Applications"):
        raise ValueError("expected candidate app and /Applications link")
    if not background.is_file():
        raise ValueError("missing candidate background")
    store_path = volume / ".DS_Store"
    if store_path.exists():
        raise FileExistsError("refusing to replace existing layout metadata")
    alias = Alias.for_file(str(background)).to_bytes()
    with DSStore.open(str(store_path), "w+") as store:
        store["."]["bwsp"] = {
            "ShowStatusBar": False, "ShowToolbar": False, "ShowTabView": False,
            "ContainerShowSidebar": False, "ShowSidebar": False,
            "WindowBounds": "{{200, 120}, {660, 400}}",
        }
        store["."]["icvp"] = {
            "backgroundType": 2, "backgroundImageAlias": alias,
            "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
            "showIconPreview": True, "showItemInfo": False, "textSize": 12.0,
            "viewOptionsVersion": 1, "arrangeBy": "none", "labelOnBottom": True,
            "iconSize": 128.0, "gridSpacing": 100.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0,
        }
        store["."]["vstl"] = ("type", b"icnv")
        store["顶屿.app"]["Iloc"] = (170, 190)
        store["Applications"]["Iloc"] = (490, 190)
    with DSStore.open(str(store_path), "r") as store:
        assert store["顶屿.app"]["Iloc"] == (170, 190)
        assert store["Applications"]["Iloc"] == (490, 190)
        assert store["."]["bwsp"]["WindowBounds"] == "{{200, 120}, {660, 400}}"
        assert store["."]["icvp"]["backgroundImageAlias"] == alias
    print("Finder layout metadata written and verified; no UI automation")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("volume", type=Path)
    create_layout(parser.parse_args().volume.resolve())
