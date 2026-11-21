wimlib 1.14.5 - bundled third-party software
============================================

This folder contains an unmodified Windows x64 build of wimlib 1.14.5, used by
Simple-WIM2ESD---ESD2WIM-Converter.ps1 as an optional, multi-threaded export
engine. wimlib is a separate program by Eric Biggers and is NOT covered by the
AGPL license of this repository.

Files
-----
wimlib-imagex.exe               command line tool (wimlib 1.14.5, x86-64)
libwim-15.dll                   wimlib library (required by wimlib-imagex.exe)
COPYING                         wimlib license overview
COPYING.GPLv3                   GNU General Public License v3
COPYING.LGPL                    GNU Lesser General Public License v2.1
wimlib-1.14.5-source.tar.gz     complete source code of wimlib 1.14.5
                                (git tag v1.14.5 of https://github.com/ebiggers/wimlib)

SHA-256
-------
34c0c4165591ad1f592837ed99d08273c58d6ed3fe0ed6360cf34e7b0739b353  wimlib-imagex.exe
ba853ee1e3fc5f5798581f02e8e066ba07a0a2375f0bf444fe981431fd508495  libwim-15.dll

License
-------
wimlib may be redistributed and/or modified under the terms of the GNU General
Public License, version 3 or (at your option) any later version. libwim (the
library, libwim-15.dll) may alternatively be used under the GNU Lesser General
Public License, version 2.1 or later. See COPYING for details.
There is NO WARRANTY, to the extent permitted by law.

Source code
-----------
The corresponding source code is included in wimlib-1.14.5-source.tar.gz.
It is also available from the official website https://wimlib.net/ and from
https://github.com/ebiggers/wimlib (tag v1.14.5).

Updating
--------
To use a newer wimlib version, replace wimlib-imagex.exe and libwim-15.dll with
the files from the official Windows package on https://wimlib.net/ and replace
the source archive accordingly. Alternatively, delete this folder to use DISM only.
