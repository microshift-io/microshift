#!/usr/bin/env python

import specfile
from itertools import product

pkgs_to_remove = [
    'multus',
    'low-latency',
    'gateway-api',
    'ai-model-serving',
    'cert-manager',
    'observability',
]

sections_to_remove = [
    'package',
    'description',
    'files',
    'preun',
    'post',
]

full_sections_to_remove = [ f"{p[0]} {p[1]}{p[2]}" for p in product(sections_to_remove, pkgs_to_remove, ["", "-release-info"]) ]

install_keywords_to_remove = [ 
    'multus',
    'low-latency',
    'lib/tuned',
    '05-high-performance-runtime.conf',
    'microshift-baseline',
    'microshift-tuned',
    'gateway-api',
    'ai-model-serving',
    'cert-manager',
    'observability',
]

s = specfile.Specfile('./packaging/rpm/microshift.spec', macros=[('release', '1'), ('version', '4.0.0'), ('commit', 'x'), ('embedded_git_tag', 'tag'), ('embedded_git_tree_state', 'clean')])

with s.sections() as sections:
    for id in full_sections_to_remove:
        try:
            sec = sections.get(id)
            sections.remove(sec)
            print(f"Removing section: '%{id}'")
        except ValueError as e:
            pass

    i = sections.install
    new_install = []
    nl_present = False
    for line in i:
        if any(substring in line for substring in install_keywords_to_remove):
            print(f"Removing line: '{line}'")
        else:
            if line == "":
                # Skip extraneous newlines for aesthetic reasons
                if nl_present:
                    continue
                else:
                    nl_present = True
                    new_install.append(line)
            else:
                nl_present = False
                new_install.append(line)
    i.clear()
    i.extend(new_install)

s.save()