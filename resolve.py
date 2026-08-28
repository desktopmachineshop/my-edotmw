# -*- coding: utf-8 -*-
"""Resolve conflict markers in a file by a stated policy.

  python resolve.py <file> ours|theirs|both

Used by the union build so every resolution is a recorded policy rather
than a hand edit nobody can audit afterwards.
"""
import io, sys

path, policy = sys.argv[1], sys.argv[2]
lines = io.open(path, encoding='utf-8', newline='').read().split('\n')
out, mode, hunks = [], None, 0
ours, theirs = [], []

for line in lines:
    if line.startswith('<<<<<<<'):
        mode, ours, theirs = 'ours', [], []
        hunks += 1
        continue
    if line.startswith('=======') and mode == 'ours':
        mode = 'theirs'
        continue
    if line.startswith('>>>>>>>') and mode == 'theirs':
        out += ours if policy == 'ours' else theirs if policy == 'theirs' else ours + theirs
        mode = None
        continue
    if mode == 'ours':
        ours.append(line)
    elif mode == 'theirs':
        theirs.append(line)
    else:
        out.append(line)

assert mode is None, 'unterminated conflict hunk in %s' % path
io.open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
print('%s: %d hunk(s) resolved as %s' % (path, hunks, policy))
