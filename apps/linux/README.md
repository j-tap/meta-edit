# MetaEdit for Linux

Planned. Native GNOME app: Python 3.11+, GTK 4, libadwaita, mutagen for audio tags, GExiv2 for image
metadata, extended attributes (`user.xdg.*`) for file attributes.

Layout when it lands:

```
metaedit/           Python package: providers, field model, UI
data/               desktop entry, app id metainfo, icons
packaging/          Flatpak manifest, Debian control files
```

Build: Flatpak bundle via `flatpak-builder`, Debian package via `dpkg-deb`. For development on any system
with GTK 4 and libadwaita installed: `python -m metaedit`.
