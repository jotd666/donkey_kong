import os,re,pathlib

this_dir = pathlib.Path(os.path.abspath(os.path.dirname(__file__)))

re_blit = re.compile("^\s+move\.([wl])\s+(#?[\-\w]+),(blt\w+)\(a5\)(.*)",flags=re.I)
srcname = "amiga.68k"
srcfile = this_dir.parent / "src/amiga" / srcname
dstfile = this_dir / srcname


def repl_blit(m):
    size,value,offset,rest = m.groups()
    if size.lower() == 'l':
       line = f"WRITE_BLITTER_REG_LONG\t{value},{offset}"
    elif offset == "bltsize":
        line = f"WRITE_BLITTER_REG_SIZE\t{value}"
    else:
       line = f"WRITE_BLITTER_REG_WORD\t{value},{offset}"
    return f"\t{line}{rest}"

with open(srcfile) as f, open(dstfile,"w") as fw:
    for line in f:
        line = re_blit.sub(repl_blit,line)
        fw.write(line)
