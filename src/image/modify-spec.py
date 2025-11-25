#!/usr/bin/env python

"""
Following script modifies downstream microshift.spec to remove packages not yet supported by the upstream.

When some package will be supported by the upstream, remove the package name from the pkgs_to_remove list and right keywords from the install_keywords_to_remove list.
"""

import specfile
from itertools import product

# Subpackages to remove
pkgs_to_remove = [
    'multus',
    'low-latency',
    'gateway-api',
    'ai-model-serving',
    'cert-manager',
    'observability',
]

# Sections to remove for the subpackages
sections_to_remove = [
    'package',
    'description',
    'files',
    'preun',
    'post',
]

# Product of pkgs_to_remove and sections_to_remove, and the '-release-info' suffix.
# Result is a list of strings like: 'package multus', 'description multus', 'files multus-release-info', etc.
full_sections_to_remove = [ f"{p[0]} {p[1]}{p[2]}" for p in product(sections_to_remove, pkgs_to_remove, ["", "-release-info"]) ]

# Words that identify lines to remove from the install section.
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

s = specfile.Specfile(
    './packaging/rpm/microshift.spec',
    # Dummy macro values - they are referenced in the spec file but not provided by default, only added when running make-rpm.sh.
    # Without these, specfile cannot be parsed because of the recursive references (because microshift.spec actually redefines macros defined by default...)
    macros=[('release', '1'), ('version', '4.0.0'), ('commit', 'x'), ('embedded_git_tag', 'tag'), ('embedded_git_tree_state', 'clean')])

with s.sections() as sections:
    for id in full_sections_to_remove:
        try:
            sec = sections.get(id)
            sections.remove(sec)
            print(f"Removing section: '%{id}'")
        except ValueError as e:
            # Ignore non-existent sections
            pass

    i = sections.install
    new_install = []
    nl_present = False
    for line in i:
        # If the line contains any of the keywords - remove the line (= don't append to new_install)
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
