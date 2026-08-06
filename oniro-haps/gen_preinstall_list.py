#!/usr/bin/env python3
# Copyright (c) 2026 Eclipse Oniro for OpenHarmony contributors.
# SPDX-License-Identifier: Apache-2.0
"""Splice the Oniro distribution HAPs into the product's preinstall list.

The committed install_list.json describes the default (stock) image, which
carries no Oniro-built HAP. When the build opts in with
`oniro_install_custom_haps=true`, BMS also needs a preinstall entry per
installed bundle, or the HAPs land in /system/app but are never installed.

Entries are derived from oniro-haps.json so the descriptor stays the single
source of truth: an app added there needs no change here.
"""
import argparse
import json


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--install-list', required=True,
                    help='committed stock install_list.json')
    ap.add_argument('--descriptor', required=True,
                    help='oniro-haps.json')
    ap.add_argument('--output', required=True)
    ap.add_argument('--skip-optional', action='store_true',
                    help="omit apps marked 'optional' (matches "
                         'oniro_include_florisboard=false)')
    args = ap.parse_args()

    with open(args.install_list, encoding='utf-8') as f:
        install_list = json.load(f)
    with open(args.descriptor, encoding='utf-8') as f:
        descriptor = json.load(f)

    entries = install_list.setdefault('install_list', [])
    present = {e.get('app_dir') for e in entries}

    for app in descriptor['apps']:
        if args.skip_optional and app.get('optional'):
            continue
        for module in app['modules']:
            app_dir = '/system/' + module['install_dir']
            if app_dir in present:
                continue
            # Removable: these are add-on applications, not platform services,
            # so the user must be able to uninstall them.
            entries.append({'app_dir': app_dir, 'removable': True})
            present.add(app_dir)

    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(install_list, f, indent=4, ensure_ascii=False)
        f.write('\n')


if __name__ == '__main__':
    main()
