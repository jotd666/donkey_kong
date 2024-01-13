# quick&dirty
import re,collections
import config

depth = 4

possible_issues = []

with open(config.asm_file_68k) as f:
    d = collections.deque(maxlen=depth)
    for i,line in enumerate(f,1):
        line = line.strip()
        if not line.startswith("*"):
            words = {x for x in re.split("\W",line) if x}

            for areg,dreg1,dreg2 in (("a0",'d5',"d6"),('a1',"d3","d4")):
                a0_in_words = areg in words
                d6_in_words = dreg1 in words or dreg2 in words

                if a0_in_words or d6_in_words:
                    for p_i,p_line,p_words in d:
                        if (a0_in_words and (dreg1 in p_words or dreg2 in p_words)) or (d6_in_words and areg in p_words):
                            # try to rule out stuff
                            if any(x in words for x in ("movem","lea")):
                                # means that a0 overrides the d6 value
                                continue
                            possible_issues.append((p_i,p_line,i,line))

                            d.clear()
                            break

            d.append((i,line,words))

for p_i,p_line,i,line in sorted(possible_issues):
    print("====> Possible issue:")
    print(f"{p_i}: {p_line}")
    print(f"{i}: {line}")

print(f"total: {len(possible_issues)}")