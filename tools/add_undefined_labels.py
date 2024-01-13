import re,subprocess,os

def add_undefined_labels(asmname):
    ud = re.compile("undefined reference to `l_(\w+)'")
    build = ['cmd', '/c', 'wmake.py','-m',"../makefile.am"]
    p = subprocess.run(build,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,cwd="../src")

    general_instruction_re = re.compile(r"^\s+\b([^\s]*)\b\s*([^\s]*)\s*\| \[\$([a-f0-9]{4,}):")



    if p.returncode:
        undefs = set()
        for line in p.stderr.decode().splitlines():

            m = ud.search(line)
            if m:
                undefs.add(int(m.group(1),16))


        lines = []
        address_lines = {}
        with open(asmname) as f:
            for i,line in enumerate(f):
                lines.append(line)
                m = general_instruction_re.match(line)
                if m:
                    address_lines[int(m.group(3),16)] = i

        for u in undefs:
            offset = 0
            lineno = address_lines.get(u)
            if lineno is None:
                offset = 2
                lineno = address_lines.get(u-2)
            if lineno is None:
                offset = 4
                lineno = address_lines.get(u-4)
            if lineno is None:
                offset = 6
                lineno = address_lines.get(u-6)

            if lineno is None or offset:
                print("not done {} {} {} look for ;{:04x}".format(lineno,hex(u),offset,u-6))
            else:
                lines[lineno] = "l_{:04x}:\n{}".format(u,lines[lineno])
        with open(asmname+"new","w") as f:
            f.writelines(lines)


add_undefined_labels("../src/donkey_kong.68k")