# foo2zjs for the HP LaserJet P1102 on macOS (Apple silicon)

Build scripts that compile the open-source [foo2zjs](http://foo2zjs.rkkda.com/)
printer driver, as packaged by [Debian/Ubuntu](https://salsa.debian.org/printing-team/foo2zjs),
for macOS on Apple silicon, so a Mac can print to an HP LaserJet Professional P1102 over USB.

> **Unofficial community project.** Not affiliated with, endorsed by or supported by
> HP Inc. or Apple Inc. See [Trademarks](#trademarks).

**Symptom this addressed on the tested setup:** macOS added the printer over USB,
jobs appeared to print, the printer's green light was on, and no page came out.

## Why the printer prints nothing

- **A generic driver was selected.** On the tested Mac, with no vendor driver
  installed, the printer was set up with the generic "HP DeskJet Series" PPD.
  The P1102 is a host-based printer that expects the ZjStream format, which that
  driver does not produce, so nothing printed.
- **The vendor driver package did not fit this setup.** The HP printer driver
  package for macOS that we examined (`HewlettPackardPrinterDrivers.pkg`, downloaded
  November 2026) has an installer check that stops on macOS versions later than
  15.0, and its P1100-series filter (`rastertozjs`) is built for Intel (x86_64)
  only. Running it on Apple silicon needs Rosetta, which the tested Mac did not
  have. Check HP's support site for current options before using this project.
- **Linux uses foo2zjs.** The Ubuntu machine that printed to the same printer
  used foo2zjs (`-z2` model). This project builds that driver for macOS.

## Install

Requires Xcode command line tools (`xcode-select --install`) and an admin account.

```sh
git clone <this repo> p1102-mac && cd p1102-mac
./build.sh        # ~5 min the first time (compiles Ghostscript)
./install.sh      # asks for your password
./test-print.sh   # prints two pages: "Page 1 of 2", "Page 2 of 2"
```

Then print from any app. `install.sh` adds the USB printer as
`HP_LaserJet_Professional_P1102` and makes it the default.

If you already added the printer and it prints nothing, remove it first in
**System Settings → Printers & Scanners**, or with `lpadmin -x <name>`.
`install.sh` will not replace an existing printer of the same name.

To remove everything: `./uninstall.sh`.

## What gets built and installed

| Installed to | What |
|---|---|
| `/Library/Printers/foo2zjs/bin/foo2zjs`, `foo2zjs-wrapper`, `foo2zjs-pstops` | The foo2zjs driver, from Ubuntu's source package `foo2zjs_20200505dfsg0-3ubuntu1` with Ubuntu's patches applied |
| `/Library/Printers/foo2zjs/bin/gs` | Ghostscript 10.08.0, built from Artifex's release with its bundled libraries only |
| `/Library/Printers/foo2zjs/filter/foo2zjs-cups` | CUPS filter: reads the print options and calls the foo2zjs wrapper |
| `/Library/Printers/PPDs/Contents/Resources/HP-LaserJet_Pro_P1102-foo2zjs-macos.ppd` | foo2zjs's P1102 PPD, adapted for macOS |

Every download is checked against a pinned SHA-256: Ubuntu's published checksums
for foo2zjs, and the release checksum for Ghostscript.

## What had to change for macOS

On Linux the pipeline is `foomatic-rip → foo2zjs-wrapper → gs → foo2zjs`.
On macOS, four things are different:

1. **No foomatic-rip.** `foo2zjs-cups` does its job for this PPD: each option's
   value comes from the job or the PPD default, and its command-line flags come
   from the PPD's own `*FoomaticRIPOptionSetting` line.
2. **CUPS runs filters in a sandbox.** In testing, the filter could not reach a
   Homebrew Ghostscript in `/opt/homebrew` when run by CUPS, although it worked
   from a terminal. So the driver installs its own Ghostscript under
   `/Library/Printers`, and `build.sh` fails if that Ghostscript links any library
   outside macOS.
3. **`foo2zjs-pstops` wants GNU sed on macOS.** For this mono printer the wrapper
   only uses the `-n` path, where macOS `sed` gives byte-identical output, so the
   build switches it to the system `sed`.
4. **Copies, N-up and the default paper.** The macOS print dialog does copies and
   N-up itself, so those options are removed from the PPD, and the default paper is A4.

## How it is verified

- **On every build:** `build.sh` runs the real filter on the built files with an
  empty environment, as CUPS would, decodes the result with foo2zjs's `zjsdecode`,
  and fails unless a complete page comes out.
- **During development:** the printer data was decoded back into an image and
  compared with the source page. Real prints came out right on A4: a single test
  page sent straight to the printer, and a 2-page PDF printed through the
  installed queue.

Tested on:

| | |
|---|---|
| macOS | 27.0.1, Apple silicon (arm64), no Rosetta |
| Printer | HP LaserJet Professional P1102, USB ID `03f0:002a` |
| Paper | A4 |

Letter and the other paper sizes in the PPD are mapped to the right foo2zjs codes
but have not been printed. Pull requests with test reports are welcome.

## Other models

foo2zjs's `-z2` model also covers the P1566 and P1606dn, and foo2zjs ships a
separate PPD for the P1102w. This project only installs the P1102 PPD and has
only been tested on the P1102.
Supporting another model should mostly mean using its PPD from foo2zjs's `PPD/` folder.

## Troubleshooting

- **Job stays in the queue:** `lpstat -l -p HP_LaserJet_Professional_P1102` shows
  the filter's last error message.
- **Full filter log:** run `cupsctl --debug-logging`, print again, then
  `log show --last 5m --predicate 'process == "cupsd"'`. Turn it off with
  `cupsctl --no-debug-logging`.
- **`lpadmin` warns that printer drivers are deprecated:** CUPS prints this for
  any PPD-based driver ("Printer drivers are deprecated and will stop working in
  a future version of CUPS"). Printing worked on the tested version.

## Credits and licences

- [foo2zjs](http://foo2zjs.rkkda.com/), maintained by Rick Richardson, GPL-2.0-or-later,
  and the [Debian/Ubuntu packaging and patches](https://salsa.debian.org/printing-team/foo2zjs).
- [Ghostscript](https://ghostscript.com/) by Artifex Software, AGPL-3.0-or-later
  (some bundled components are under other licences; see its `LICENSE`).

This repository contains only the build, install and filter scripts (MIT, see
[LICENSE](LICENSE)). It downloads foo2zjs and Ghostscript at build time. It
contains no HP or Apple software, firmware or artwork, and it does not modify or
redistribute any. If you redistribute the built files from `stage/`, their own
licences apply.

## No warranty

The scripts install files under `/Library/Printers` and add a printer, using
administrator rights. Read them before running them. They are provided as is,
without warranty of any kind (see [LICENSE](LICENSE)); use at your own risk.

## Trademarks

HP and LaserJet are trademarks of HP Inc. or its affiliates. Apple, Mac, macOS,
Apple silicon, Rosetta and Xcode are trademarks of Apple Inc. Other names may be
trademarks of their owners. They are used here only to identify the hardware and
operating system this project is compatible with; no affiliation or endorsement
is implied.
