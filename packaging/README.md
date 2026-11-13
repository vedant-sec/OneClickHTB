# Packaging

## AUR (`oneclickhtb`)

`PKGBUILD` installs the plasmoid system-wide into
`/usr/share/plasma/plasmoids/`, plus the icon and the license.

**Before submitting to the AUR**, the GitHub repository must be public —
otherwise `makepkg` cannot download the tag tarball. Then:

```bash
sudo pacman -S --needed base-devel
cd packaging
updpkgsums                      # fills sha256sums in PKGBUILD
makepkg --printsrcinfo > .SRCINFO
makepkg -si                     # sanity build + install
```

Publish with:

```bash
git clone ssh://aur@aur.archlinux.org/oneclickhtb.git aur-oneclickhtb
cp PKGBUILD .SRCINFO aur-oneclickhtb/
cd aur-oneclickhtb && git add . && git commit -m "1.0.0" && git push
```

Bump flow: update `pkgver` + `pkgrel`, run `updpkgsums`, regenerate `.SRCINFO`.

## Plasma package artifact

```bash
./scripts/pack.py
# -> dist/oneclickhtb-<version>.plasmoid
```

Attach that file to the GitHub release so users can install it with
`kpackagetool6 --type Plasma/Applet --install oneclickhtb-<version>.plasmoid`
(or Plasma's *Install from file*).

> **Status:** AUR is currently not accepting new packages/users, so this package
> is not published there yet. The GitHub release artifact and `install.sh` are the
> supported install paths for now. Nothing else needs to change when the AUR
> reopens — the PKGBUILD and `.SRCINFO` are already validated with `makepkg -f`.
