import re,json

ram_start = 0x6000
ram_end = 0x7000

ram_addresses = re.compile("(\$6[0-9A-F]{3})",flags=re.I)
equates = re.compile("(\w+)\s+equ\s+([\w\+\$]+)",flags=re.I)
instruction = re.compile("^([0-9A-F]{4}:[ 0-9A-F]{13}[a-z_]\w+\s+)([^; ]+)",flags=re.I)

def parse_int(v):
    if v.startswith("$"):
        return int(v[1:],16)
    else:
        return int(v)

with open("dkong_z80.asm") as f:
    contents = f.read()
    addresses = set(ram_addresses.findall(contents))

address_dict = dict.fromkeys(addresses,None)
vars_dict = {}

for line in contents.splitlines():
    m = ram_addresses.search(line)
    if m:
        desc = "unknown"
        toks = line.split(";",maxsplit=1)
        if len(toks)==2:
            desc = toks[1].strip()
        address_dict[m.group(1)] = re.sub("[_\W]+","_",desc.lower())
    else:
        m = equates.match(line)
        if m:
            eq,val = m.groups()
            if val.startswith("RAM+"):
                vars_dict[eq.lower()] = parse_int(val.split("+")[1])
            else:
                try:
                    v = parse_int(val)
                except Exception:
                    print("not resolved equate: ",val)

##with open("varnames.json","w") as f:
##    json.dump(address_dict,f,indent=2,sort_keys=True)
with open("variable_names.json","r") as f:
    address_dict = json.load(f)

def format_variable_name(t):
    parents = False
    if t.startswith("("):
        t = t.strip("()")
        parents = True
    if t.startswith("$"):
        tv = parse_int(t)
        tn = address_dict.get(t)
        if not tn:
            if ram_start < tv < ram_end:
                tn = "unknown_"+t.strip("$")
            else:
                # don't change
                tn = t
        else:
            tn = "{}_{}".format(tn,t.strip("$"))
        t = tn
    else:
        # try to look into equates
        tn = vars_dict.get(t)
        if tn:
            t = "{}_{:04x}".format(t,ram_start+tn)


    if parents:
        t = f"({t})"
    return t


def rename_variable(m):
    start,rest = m.groups()
    toks = rest.split(",")
    if len(toks) == 2:
        new_toks = [format_variable_name(t) for t in toks]
        rest = ",".join(new_toks)
    else:
        rest = format_variable_name(rest)
    return start+rest


# second pass
with open("dkong_z80_.asm","w") as f:
    for line in contents.splitlines():
        line = instruction.sub(rename_variable,line)
        f.write(line)
        f.write("\n")


