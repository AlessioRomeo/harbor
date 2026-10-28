# dmgbuild settings for Harbor's disk image. scripts/release.sh runs it from the repo root and
# passes the app as `-D app=<path>`.
import os.path

app = defines["app"]

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

# Matches the 640 x 400 pt background drawn by scripts/make-dmg-background.swift.
background = "Resources/dmg-background.tiff"
window_rect = ((200, 120), (640, 400))
icon_size = 112
text_size = 13
icon_locations = {"Harbor.app": (170, 190), "Applications": (470, 190)}

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
