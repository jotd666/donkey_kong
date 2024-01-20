import os,re,bitplanelib,ast
from PIL import Image,ImageOps


import collections


#transparent = (60,100,200)  # whatever is not a used RGB is ok


# only 1 4 color palette, all rows use 4 colors per row
# those colors can't be found in palette
fake_4_color_palette = [(0,0,0),(0xE0,0,0),(0,0xE0,0),(0,0,0xE0)]


this_dir = os.path.dirname(__file__)
src_dir = os.path.join(this_dir,"../../src/amiga")
dump_dir = os.path.join(this_dir,"dumps")
dump_tiles_dir = os.path.join(dump_dir,"tiles")
dump_palettes_dir = os.path.join(dump_dir,"palettes")
dump_sprites_dir = os.path.join(dump_dir,"sprites")
uncategorized_dump_sprites_dir = os.path.join(dump_sprites_dir,"__uncategorized")
def ensure_empty(sd):
    if os.path.exists(sd):
        for p in os.listdir(sd):
            n = os.path.join(sd,p)
            if os.path.isfile(n):
                os.remove(n)
    else:
        os.mkdir(sd)

dump_tiles = False
dump_sprites = True
dump_palettes = False

if dump_palettes:
    ensure_empty(dump_dir)
    ensure_empty(dump_palettes_dir)

if dump_tiles:
    ensure_empty(dump_dir)
    ensure_empty(dump_tiles_dir)

if dump_sprites:
    ensure_empty(dump_dir)
    ensure_empty(dump_sprites_dir)
    ensure_empty(uncategorized_dump_sprites_dir)


NB_POSSIBLE_SPRITES = 128
NB_BOB_PLANES = 5

def guess_cluts():

    # the palette scheme is bizarre and I don't want to dig into MAME source to undestand it so
    # I'm booting the game with palettes 0, 1, 2, 3 set with a girder containing 3 colors instead
    # of empty char, and I snapshot the pics. The girder is a nice tile: it contains all 3 nonblack colors
    # (else it would fails) and even better, it contains them in the first column of the tile. So scanning only
    # one LINE of the image is enough to collect the colors

    rval = []
    for i in range(0,4):
        bank = os.path.join(this_dir,f"palettes/bank_{i:02}.png")
        img = Image.open(bank)
        # snapshot of palette 1 is incomplete/not refreshed
        x_start = 0 if i==1 else img.size[0]-8
        row_cols = []
        for y_start in range(0,img.size[1],8):
            clut_order = iter([3,1,2])
            non_black_colors = [(0,0,0)]*4
            non_black_colors_set = set()
            for y in range(8):
                color = img.getpixel((x_start,y_start+y))
                # collect non-black colors, preserving order. The girder tile starts by color 3
                # (dotted lines), then color 2 (line) then color 1 (cross bars)
                # first row palette CLUT entry is 0, last row entry is 3

                if len(non_black_colors_set) < 3 and color != (0,0,0) and color not in non_black_colors_set:
                    non_black_colors_set.add(color)
                    non_black_colors[next(clut_order)] = color
            row_cols.append(non_black_colors)
        rval.append(row_cols)
    return rval




def dump_asm_bytes(*args,**kwargs):
    bitplanelib.dump_asm_bytes(*args,**kwargs,mit_format=True)


sprite_config = dict()

def add_sprite_block(start,end,prefix,cluts,is_sprite=False,mirror=False):
    if isinstance(cluts,int):
        cluts = [cluts]
    for i in range(start,end):
        if i in sprite_config:
            # merge
            sprite_config[i]["cluts"].extend(cluts)
        else:
            sprite_config[i] = {"name":f"{prefix}_{i:02x}","cluts":cluts,"is_sprite":is_sprite,"mirror":mirror}

def add_sprite(code,prefix,cluts,is_sprite=False,mirror=False):
    add_sprite_block(code,code+1,prefix,cluts,is_sprite,mirror)

add_sprite_block(0,7,"mario",2,mirror=True)
add_sprite_block(8,0x10,"mario",2,mirror=True)
add_sprite_block(0x78,0x7B,"mario_dies",2,mirror=True)
add_sprite_block(0x10,0x14,"princess",9,mirror=True)
add_sprite(0x12,"princess",10)
add_sprite(0x14,"princess",10,mirror=True)  # used when donkey kong takes her under his arm
add_sprite(7,"blank",2)

add_sprite_block(0x15,0x19,"barrel",11,mirror=True)
add_sprite(0x49,"oil_barrel",12)
add_sprite_block(0x19,0x1C,"death_barrel",12,mirror=True)
add_sprite_block(0x1E,0x20,"hammer",[1,7],mirror=True)
add_sprite_block(0x20,0x38,"kong",8,mirror=True)
add_sprite_block(0x23,0x24,"kong",7)
add_sprite(0x70,"blank",[1,8,10])
add_sprite_block(0x4d,0x4f,"firefox",[0,1])
add_sprite_block(0x3b,0x3e,"bouncer",0)
add_sprite_block(0x73,0x76,"bonus",0xA)
add_sprite_block(0x76,0x78,"heart",9)
add_sprite(0x39,"sparkle",1)
add_sprite(0x3A,"blank",15)
add_sprite(0x3F,"blank",0xC)



#add_sprite_block(0x3B,0x3D,"bouncer",[1,2,3]) # clut?
add_sprite_block(0x3D,0x3F,"fireball",[0,1])
add_sprite_block(0x40,0x44,"flame",[1])

add_sprite(0x44,"elevator",3) # clut?
add_sprite(0x45,"conveyor",0xF) # clut?
add_sprite(0x46,"moving_ladder",0x0) # clut?

block_dict = {}

# hackish convert of c gfx table to dict of lists
# (Thanks to Mark Mc Dougall for providing the ripped gfx as C tables)
with open(os.path.join(this_dir,"..","dkong_gfx.c")) as f:
    block = []
    block_name = ""
    start_block = False

    for line in f:
        if "uint8" in line:
            # start group
            start_block = True
            if block:
                txt = "".join(block).strip().strip(";")
                block_dict[block_name] = {"size":size,"data":ast.literal_eval(txt)}
                block = []
            block_name = line.split()[1].split("[")[0]
            try:
                size = int(line.split("[")[-1].split("]")[0])
            except ValueError:
                size = 0
        elif start_block:
            line = re.sub("//.*","",line)
            line = line.replace("{","[").replace("}","]")
            block.append(line)

    if block:
        txt = "".join(block).strip().strip(";")
        block_dict[block_name] = {"size":size,"data":ast.literal_eval(txt)}

# block_dict structure is as follows:
# dict_keys(['palette', 'clut', 'tile', 'sprite'])


def replace_color(img,color,replacement_color):
    rval = Image.new("RGB",img.size)
    for x in range(img.size[0]):
        for y in range(img.size[1]):
            c = (x,y)
            rgb = img.getpixel(c)
            if rgb == color:
                rgb = replacement_color
            rval.putpixel(c,rgb)
    return rval

def swap(a,i,j):
    a[j],a[i] = a[i],a[j]

def get_sprite_clut(clut_index):
    # simple slice of global palette
    rval = tile_palette[clut_index*4:(clut_index+1)*4]
    # needs some reordering
    swap(rval,1,2)
    return rval

# creating the sprite configuration in the code is more flexible than with a config file


def add_sprite_block(start,end,prefix,cluts,is_sprite):
    if isinstance(cluts,int):
        cluts = [cluts]
    for i in range(start,end+1):
        sprite_config[i] = {"name":f"{prefix}_{i:02x}","cluts":cluts,"is_sprite":is_sprite}





#add_sprite_block(0x9,0x10,"falling_jeep",jeep_cluts,True)



def switch_values(t,a,b):
    t[a],t[b] = t[b],t[a]


tile_palette = [(r*8,g*8,b*8) for r,g,b in block_dict["palette"]["data"]]

# unique colors, much smaller (18)
# start by fake colors (black first, then 3 colors not in palette
# to avoid 4 first tile colors=
bobs_palette = fake_4_color_palette + sorted(set(tile_palette))[1:]
bobs_palette += [fake_4_color_palette[0]]*(32-len(bobs_palette))


rval = guess_cluts()
# dump cluts as RGB4 for sprites
with open(os.path.join(src_dir,"row_colors.68k"),"w") as f:
    # 4 palette configs
    f.write("palette_table:\n")
    for i in range(4):
        f.write(f"\t.long\tpalette_{i}\n")
    f.write("\n")

    for i,config in enumerate(rval):
        f.write(f"palette_{i}:\n")
        for row in config:
            rgb4 = [bitplanelib.to_rgb4_color(x) for x in row[1:]]  # don't dump black
            bitplanelib.dump_asm_bytes(rgb4,f,mit_format=True,size=2)



with open(os.path.join(src_dir,"palette.68k"),"w") as f:
    bitplanelib.palette_dump(bobs_palette,f,pformat=bitplanelib.PALETTE_FORMAT_ASMGNU)


character_codes = []

if True:
    for k,chardat in enumerate(block_dict["tile"]["data"]):
        img = Image.new('RGB',(8,8))

        d = iter(chardat)
        for i in range(8):
            for j in range(8):
                v = next(d)
                img.putpixel((j,i),fake_4_color_palette[v])
        character_codes.append(bitplanelib.palette_image2raw(img,None,fake_4_color_palette))

        if dump_tiles:
            scaled = ImageOps.scale(img,5,0)
            scaled.save(os.path.join(dump_tiles_dir,f"char_{k:02x}.png"))


bobs_used_colors = collections.Counter()
sprites_used_colors = collections.Counter()

sprites = dict()
bitplane_cache = dict()
plane_next_index = 0

if True:
    for k,sprdat in enumerate(block_dict["sprite"]["data"]):
        sprconf = sprite_config.get(k)
        if sprconf:
            clut_range = sprconf["cluts"]
            name = sprconf["name"]
            is_sprite = sprconf["is_sprite"]
        else:
            clut_range = [0,1,2,3]
            name = f"unknown_{k:02x}"
            is_sprite = False

        for cidx in clut_range:
            hsize = 16
            img = Image.new('RGB',(16,hsize))
            spritepal = get_sprite_clut(cidx)

            d = iter(sprdat)
            for j in range(16):
                for i in range(16):
                    v = next(d)
                    color = spritepal[v]
                    if sprconf:
                        (sprites_used_colors if is_sprite else bobs_used_colors)[color] += 1
                    img.putpixel((i,j),color)

            # only consider sprites/cluts which are pre-registered
            if sprconf:
                if k not in sprites:
                    sprites[k] = {"is_sprite":is_sprite,"name":name,"hsize":hsize,"mirror":sprconf["mirror"]}
                cs = sprites[k]

                if is_sprite:
                    # hardware sprites only need one bitmap data, copied 8 times to be able
                    # to be assigned several times. Doesn't happen a lot in this game for now
                    # but at least wheels have more than 1 instance
                    if "bitmap" not in cs:
                        # create entry only if not already created (multiple cluts)
                        # we must not introduce a all black or missing colors palette in here
                        # (even if the CLUT may be used for this sprite) else base image will miss colors!
                        #
                        # example: pengo all-black enemies. If this case occurs, just omit this dummy config
                        # the amiga engine will manage anyway
                        #
                        cs["bitmap"] = bitplanelib.palette_image2sprite(img,None,spritepal,
                                palette_precision_mask=0xFF,sprite_fmode=0,with_control_words=True)
                else:
                    # software sprites (bobs) need one copy of bitmaps per palette setup. There are 3 or 4 planes
                    # (4 ATM but will switch to dual playfield)
                    # but not all planes are active as game sprites have max 3 colors (+ transparent)
                    if "bitmap" not in cs:
                        cs["bitmap"] = dict()

                    csb = cs["bitmap"]

                    # prior to dump the image to amiga bitplanes, don't forget to replace brown by blue
                    # as we forcefully removed it from the palette to make it fit to 16 colors, don't worry, the
                    # copper will put the proper color back again
##                    img_to_raw = replace_color(img,brown_rock_color,blue_dark_mountain_color)
##                    img_to_raw = replace_color(img_to_raw,almost_black_color,deep_brown_color)
                    img_to_raw = img

                    plane_list = []
                    for mirrored in range(2):
                        bitplanes = bitplanelib.palette_image2raw(img_to_raw,None,bobs_palette,forced_nb_planes=NB_BOB_PLANES,
                            palette_precision_mask=0xFF,generate_mask=True,blit_pad=True)
                        bitplane_size = len(bitplanes)//(NB_BOB_PLANES+1)  # don't forget bob mask!


                        for ci in range(0,len(bitplanes),bitplane_size):
                            plane = bitplanes[ci:ci+bitplane_size]
                            if not any(plane):
                                # only zeroes
                                plane_list.append(None)
                            else:
                                plane_index = bitplane_cache.get(plane)
                                if plane_index is None:
                                    bitplane_cache[plane] = plane_next_index
                                    plane_index = plane_next_index
                                    plane_next_index += 1
                                plane_list.append(plane_index)
                        if cs["mirror"] and mirrored==0:
                            # we need do re-iterate with opposite Y-flip image (donkey kong)
                            img_to_raw = ImageOps.mirror(img_to_raw)
                        else:
                            # no mirror: don't do it once more
                            break

                    # plane list size varies depending on mirror or not
                    csb[cidx] = plane_list

            if dump_sprites:
                scaled = ImageOps.scale(img,2,0)
                if sprconf:
                    scaled.save(os.path.join(dump_sprites_dir,f"{name}_{cidx}.png"))
                else:
                    scaled.save(os.path.join(uncategorized_dump_sprites_dir,f"sprites_{k:02x}_{cidx}.png"))


with open(os.path.join(src_dir,"graphics.68k"),"w") as f:
    f.write("\t.global\tcharacter_table\n")
    f.write("\t.global\tsprite_table\n")
    f.write("\t.global\tbob_table\n")

    f.write("character_table:\n")
    for i,c in enumerate(character_codes):
        f.write(f"\t.long\tchar_{i}\n")
    for i,c in enumerate(character_codes):
        if c is not None:
            f.write(f"char_{i}:")
            bitplanelib.dump_asm_bytes(c,f,mit_format=True)

##    f.write("sprite_table:\n")
##
##    sprite_names = [None]*NB_POSSIBLE_SPRITES
##    for i in range(NB_POSSIBLE_SPRITES):
##        sprite = sprites.get(i)
##        f.write("\t.long\t")
##        if sprite:
##            if sprite == True:
##                f.write("-1")  # not displayed but legal
##            else:
##                if sprite["is_sprite"]:
##                    name = sprite['name']
##                    sprite_names[i] = name
##                    f.write(name)
##                else:
##                    f.write("0")
##        else:
##            f.write("0")
##        f.write("\n")
##
##    for i in range(NB_POSSIBLE_SPRITES):
##        name = sprite_names[i]
##        if name:
##            f.write(f"{name}:\n")
##            for j in range(8):
##                f.write("\t.long\t")
##                f.write(f"{name}_{j}")
##                f.write("\n")
##
    f.write("bob_table:\n")

    bob_names = [None]*NB_POSSIBLE_SPRITES
    for i in range(NB_POSSIBLE_SPRITES):
        sprite = sprites.get(i)
        f.write("\t.long\t")
        if sprite:
            if sprite == True or sprite["is_sprite"]:
                f.write("-1")  # hardware sprite: ignore
            else:
                name = sprite["name"]
                bob_names[i] = name
                f.write(name)

        else:
            f.write("0")
        f.write("\n")

    for i in range(NB_POSSIBLE_SPRITES):
        name = bob_names[i]
        if name:
            sprite = sprites.get(i)
            f.write(f"{name}:\n")
            csb = sprite["bitmap"]
            for j in range(16):
                b = csb.get(j)
                f.write("\t.long\t")
                if b:
                    f.write(f"{name}_{j}")
                else:
                    f.write("0")   # clut not active
                f.write("\n")

    # blitter objects (bitplanes refs, can be in fastmem)
    for i in range(NB_POSSIBLE_SPRITES):
        name = bob_names[i]
        if name:
            sprite = sprites.get(i)
            bitmap = sprite["bitmap"]
            for j in range(16):
                bm = bitmap.get(j)
                if bm:
                    sprite_label = f"{name}_{j}"
                    f.write(f"{sprite_label}:\n")
                    for plane_id in bm:
                        f.write("\t.long\t")
                        if plane_id is None:
                            f.write("0")
                        else:
                            f.write(f"plane_{plane_id}")
                        f.write("\n")

    f.write("\t.section\t.datachip\n")
    # sprites
##    for i in range(NB_POSSIBLE_SPRITES):
##        name = sprite_names[i]
##        if name:
##            sprite = sprites.get(i)
##            for j in range(8):
##                # clut is valid for this sprite
##                bitmap = sprite["bitmap"]
##                sprite_label = f"{name}_{j}"
##                f.write(f"{sprite_label}:\n\t.word\t{sprite['hsize']}")
##                bitplanelib.dump_asm_bytes(bitmap,f,mit_format=True)

    f.write("\n* bitplanes\n")
    # dump bitplanes
    for k,v in bitplane_cache.items():
        f.write(f"plane_{v}:")
        bitplanelib.dump_asm_bytes(k,f,mit_format=True)
