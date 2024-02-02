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
NB_BOB_PLANES = 4

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

def add_sprite_block(start,end,prefix,cluts,is_sprite=False,mirror=False,flip=False,levels=[1,2,3,4],smart_redraw=0):
    if isinstance(cluts,int):
        cluts = [cluts]
    for i in range(start,end):
        if i in sprite_config:
            # merge
            sprite_config[i]["cluts"].extend(cluts)
        else:
            sprite_config[i] = {"name":f"{prefix}_{i:02x}","cluts":cluts,
                                "is_sprite":is_sprite,
                                "mirror":mirror,
                                "flip":flip,  # only relevant for HW sprites, else it's handled by blitter
                                "screens":levels,
                                "smart_redraw":smart_redraw}

def add_sprite(code,prefix,cluts,is_sprite=False,mirror=False,flip=False,levels=[1,2,3,4],smart_redraw=0):
    add_sprite_block(code,code+1,prefix,cluts,is_sprite,mirror,levels=levels,flip=flip,smart_redraw=smart_redraw)

add_sprite_block(0,7,"mario",2,mirror=True)
add_sprite_block(8,0x10,"mario",2,mirror=True)
add_sprite_block(0x78,0x7B,"mario_dies",2,mirror=True)
add_sprite_block(0x7B,0x80,"score_sprite",7)
add_sprite_block(0x10,0x14,"princess",9,mirror=True,smart_redraw=0xFF)
add_sprite_block(0x60,0x64,"shattered",12,levels=[1,2,4])
add_sprite(0x12,"princess",10)
add_sprite(0x14,"princess",10,mirror=True)  # used when donkey kong takes her under his arm
add_sprite(7,"blank",2)

add_sprite(0x15,"barrel",11,mirror=True,flip=True,levels=[1],is_sprite=True)
add_sprite_block(0x16,0x18,"barrel",11,mirror=True,levels=[1])
add_sprite(0x18,"stashed_barrel",11,levels=[1])   # should be a special case to blit all 4 barrels, and only in some cases
add_sprite(0x49,"oil_barrel",12,levels=[1,2])
add_sprite_block(0x40,0x44,"flame",[1],levels=[1,2])  # barrel flame

add_sprite_block(0x19,0x1C,"death_barrel",12,mirror=True,levels=[1])
add_sprite_block(0x1E,0x20,"hammer",[1,7],mirror=True,levels=[1,2,4],is_sprite=False)
add_sprite_block(0x20,0x30,"kong",[7,8],mirror=True)  # for rivets work as firefoxes = sprites
# upper part doesn't have so many conflicts
add_sprite_block(0x30,0x38,"kong",[7,8],mirror=True,smart_redraw=1<<4)  # for rivets work as firefoxes = sprites
add_sprite(0x70,"blank",[1,8,10])
add_sprite_block(0x4d,0x4f,"firefox",[0,1],mirror=True,levels=[4],is_sprite=True)
add_sprite_block(0x3b,0x3d,"bouncer",0,levels=[3])
add_sprite_block(0x73,0x76,"bonus",0xA,levels=[2,3,4])
add_sprite_block(0x76,0x78,"heart",9)
add_sprite(0x39,"sparkle",1,[4])
add_sprite(0x3A,"blank",15)
add_sprite(0x3F,"blank",0xC)
add_sprite(0x72,"square",0xC)



#add_sprite_block(0x3B,0x3D,"bouncer",[1,2,3]) # clut?
add_sprite_block(0x3D,0x3F,"fireball",[0,1],mirror=True,levels=[1,2,3])

add_sprite(0x4B,"pie",0xE,levels=[2],is_sprite=True)
add_sprite(0x44,"elevator",0x23,levels=[3],is_sprite=True)
add_sprite(0x45,"elevator_conveyor",0xF,levels=[3],smart_redraw=True)
add_sprite_block(0x50,0x53,"conveyor_wheel",0,mirror=True,levels=[2],smart_redraw=True)
add_sprite(0x46,"moving_ladder",0x13,levels=[2])


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
    rval = original_palette[clut_index*4:(clut_index+1)*4]
    # needs some reordering
    swap(rval,1,2)
    return rval

# creating the sprite configuration in the code is more flexible than with a config file


def add_sprite_block(start,end,prefix,cluts,is_sprite):
    if isinstance(cluts,int):
        cluts = [cluts]
    for i in range(start,end+1):
        sprite_config[i] = {"name":f"{prefix}_{i:02x}","cluts":cluts,"is_sprite":is_sprite}


bobs_used_colors = collections.Counter()
sprites_used_colors = collections.Counter()
hsize = 16

def generate_16x16_image(cidx,sprdat):
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
    return img

def switch_values(t,a,b):
    t[a],t[b] = t[b],t[a]


# MAME shows more accurate colors but Mark provided 5 bit colors only
original_palette = [(r*8,g*8,b*8) for r,g,b in block_dict["palette"]["data"]]

level_palette = dict()

# if palette is taken as-is, we need 32 colors to display the full game, even less than that
# but using 32 colors has a lot of disadvantages:
# - this is super slow on real hardware! (Smooth on WinUAE but smooth on MAME too...)
# - we can't use hardware sprites properly as there could be palette conflicts

# first pass: compute each level palette knowing the sprites that can be used in it
# and only them. This saves just enough colors to have 4 tile colors (variable)
# and 12 bob colors so we can use only 4 bitplanes (plus hw sprites as bonus colors
# but even without hardware sprites we have enough colors which is really
# a chance!!)

for level in [1,2,3,4]:
    colors = set()
    for k,sprdat in enumerate(block_dict["sprite"]["data"]):
        sprconf = sprite_config.get(k)
        if sprconf:
            levels = sprconf["screens"]
            is_sprite = sprconf["is_sprite"]
            if not is_sprite and level in levels:
                clut_range = sprconf["cluts"]
                name = sprconf["name"]
                for clut in clut_range:
                    img = generate_16x16_image(clut,sprdat)
                    for x in range(img.size[0]):
                        for y in range(img.size[1]):
                            colors.add(img.getpixel((x,y)))
    colors.discard((0,0,0))  # remove black!
    colors = sorted(colors)
    if len(colors)>12:
        raise Exception("Too many colors, must be <=12")
    # pad (some levels have even less colors)
    colors = colors + [fake_4_color_palette[0]]*(12-len(colors))
    # start by fake colors (black first, then 3 colors not in palette to be sure
    # bitplane conversion won't pick them (used for tile dynamic colors only!)
    level_palette[level] = fake_4_color_palette + colors

# computing palettes for all 4 levels was interesting... just to realize that the palette
# is almost the same for all levels!! and with some color swap we are able to get all levels
# on the same colors with same indexes for the colors that are shared, which is another miracle


base_palette = level_palette[1].copy()
base_palette.insert(9,(0xd8,0x90,0x50))
base_palette.pop()  # remove last (black)

screen_3_color_9 = (0xF8,0x20,0x50)
screen_palette = {x:base_palette.copy() for x in [1,2,3,4]}
screen_1_color_9 = screen_palette[3][9]
screen_palette[3][9] = screen_3_color_9   # only 2 color changes
screen_palette[3][5] = (0x90,0x00,0x00)  # only 2 color changes

# dump cluts as RGB4 for sprites
with open(os.path.join(src_dir,"palette_cluts.68k"),"w") as f:
    for clut_index in range(16):
        clut = get_sprite_clut(clut_index)   # simple slice of palette
        rgb4 = [bitplanelib.to_rgb4_color(x) for x in clut]
        bitplanelib.dump_asm_bytes(rgb4,f,mit_format=True,size=2)


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
    for k,v in sorted(screen_palette.items()):
        f.write(f"* screen {k}\n")
        bitplanelib.palette_dump(v,f,pformat=bitplanelib.PALETTE_FORMAT_ASMGNU)


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
            img = generate_16x16_image(cidx,sprdat)
            if dump_sprites:
                scaled = ImageOps.scale(img,2,0)
                if sprconf:
                    scaled.save(os.path.join(dump_sprites_dir,f"{name}_{cidx}.png"))
                else:
                    scaled.save(os.path.join(uncategorized_dump_sprites_dir,f"sprites_{k:02x}_{cidx}.png"))

            # only consider sprites/cluts which are pre-registered
            if sprconf:
                if k not in sprites:
                    sprites[k] = {"is_sprite":is_sprite,"name":name,"hsize":hsize,"mirror":sprconf["mirror"],"flip":sprconf["flip"]}
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

                        spritepal = get_sprite_clut(cidx)

                        cs["bitmap"] = [bitplanelib.palette_image2sprite(img,None,spritepal,
                                 palette_precision_mask=0xFF,sprite_fmode=0,with_control_words=True)]

                        if cs["mirror"]:
                            # we need do re-iterate with opposite Y-flip image (donkey kong)
                            cs["bitmap"].append(bitplanelib.palette_image2sprite(ImageOps.mirror(img),None,spritepal,
                             palette_precision_mask=0xFF,sprite_fmode=0,with_control_words=True))
                        else:
                            cs["bitmap"].append(None)
                        if cs["flip"]:
                            # we need do re-iterate with opposite Y-flip image (donkey kong)
                            flipped = ImageOps.flip(img)
                            cs["bitmap"].append(bitplanelib.palette_image2sprite(flipped,None,spritepal,
                             palette_precision_mask=0xFF,sprite_fmode=0,with_control_words=True))
                            cs["bitmap"].append(bitplanelib.palette_image2sprite(ImageOps.mirror(flipped),None,spritepal,
                             palette_precision_mask=0xFF,sprite_fmode=0,with_control_words=True))


                else:
                    # software sprites (bobs) need one copy of bitmaps per palette setup. There are 3 or 4 planes
                    # (4 ATM but will switch to dual playfield)
                    # but not all planes are active as game sprites have max 3 colors (+ transparent)
                    if "bitmap" not in cs:
                        cs["bitmap"] = dict()

                    bobs_palette = screen_palette[sprconf["screens"][0]]  # take first palette even if several screens
                    csb = cs["bitmap"]

                    # prior to dump the image to amiga bitplanes, don't forget to replace brown by blue
                    # as we forcefully removed it from the palette to make it fit to 16 colors, don't worry, the
                    # copper will put the proper color back again
                    img_to_raw = img

                    plane_list = []
                    #print(f"converting {name}, screen {sprconf['screens'][0]}")
                    for mirrored in range(2):
                        bitplanes = bitplanelib.palette_image2raw(img_to_raw,None,bobs_palette,forced_nb_planes=NB_BOB_PLANES,
                            palette_precision_mask=0xFF,generate_mask=True,blit_pad=True)
                        bitplane_size = len(bitplanes)//(NB_BOB_PLANES+1)  # don't forget bob mask!


                        for ci in range(0,len(bitplanes),bitplane_size):
                            plane = bitplanes[ci:ci+bitplane_size]
                            if not any(plane):
                                # only zeroes: null pointer so engine is able to optimize
                                # by not reading the zeroed data
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
                    # we allow to mask as only in some special cases there are clut indexes > 16
                    # (but seen as masked in sprite dumps. Never mind, we can make them look correct
                    # just by masking after having used the proper CLUT when creating the bitmap)
                    # - moving ladder: seems to be 0x13
                    # - elevator: seems to be 0x23
                    csb[cidx & 0xF] = plane_list

smart_redraw_flag = [0]*256
hw_sprite_flag = [0]*256
for k,v in sprite_config.items():
    if v["is_sprite"]:
        hw_sprite_flag[k] = 1
        hw_sprite_flag[k+128] = 1  # mirror code
    smf = v["smart_redraw"]
    smart_redraw_flag[k] = smf
    smart_redraw_flag[k+128] = smf  # mirror code

# create special 4 barell image for level 1
img = generate_16x16_image(11,block_dict["sprite"]["data"][0x18])
four_barrels = Image.new("RGB",(32,32))
for sx in range(0,20,10):
    for sy in range(0,32,16):
        for x in range(0,16):
            for y in range(0,16):
                p = img.getpixel((x,y))
                if p != (0,0,0):
                    four_barrels.putpixel((x+sx,y+sy),p)

with open(os.path.join(src_dir,"graphics.68k"),"w") as f:
    f.write("\t.global\tcharacter_table\n")
    f.write("\t.global\tsprite_table\n")
    f.write("\t.global\tbob_table\n")
    f.write("\t.global\thardware_sprite_flag_table\n")
    f.write("\t.global\tsmart_redraw_flag_table\n")
    f.write("\t.global\tfour_barrels_bitmap\n")

    f.write("\nhardware_sprite_flag_table:")
    bitplanelib.dump_asm_bytes(hw_sprite_flag,f,mit_format=True)
    f.write("\nsmart_redraw_flag_table:")
    bitplanelib.dump_asm_bytes(smart_redraw_flag,f,mit_format=True)

    f.write("\ncharacter_table:\n")
    for i,c in enumerate(character_codes):
        f.write(f"\t.long\tchar_{i}\n")
    for i,c in enumerate(character_codes):
        if c is not None:
            f.write(f"char_{i}:")
            bitplanelib.dump_asm_bytes(c,f,mit_format=True)


    f.write("sprite_table:\n")

    sprite_names = [None]*NB_POSSIBLE_SPRITES
    for i in range(NB_POSSIBLE_SPRITES):
        sprite = sprites.get(i)
        f.write("\t.long\t")
        if sprite:
            if sprite == True:
                f.write("-1")  # not displayed but legal
            else:
                if sprite["is_sprite"]:
                    name = sprite['name']
                    sprite_names[i] = name
                    f.write(name)
                else:
                    f.write("0")
        else:
            f.write("0")
        f.write("\n")

    for i in range(NB_POSSIBLE_SPRITES):
        name = sprite_names[i]
        if name:
            f.write(f"{name}:\n")
            for j in range(8):
                f.write("\t.long\t")
                f.write(f"{name}_{j}")
                f.write("\n")

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

    sprite_flip_type = ["normal","mirrored","flipped","flipped_mirrored"]
    for i in range(NB_POSSIBLE_SPRITES):
        name = sprite_names[i]
        if name:
            sprite = sprites.get(i)
            for j in range(8):
                # clut is valid for this sprite
                bitmap = sprite["bitmap"]
                sprite_label = f"{name}_{j}"
                f.write(f"{sprite_label}:\n")  # all sprites are of height 16 in this game
                sprite["bitmap"] = bitmap + [None]*(4-len(bitmap))

                for i,bm in zip(sprite_flip_type,sprite["bitmap"]):
                    if bm:
                        f.write(f"\t.long\t{sprite_label}_{i}\n")
                    else:
                        f.write(f"\t.long\t0\n")

    # four_barrels
    f.write("four_barrels_bitmap:\n")
    four_sprites_bitplanes = []
    fsdata = bitplanelib.palette_image2raw(four_barrels,None,bobs_palette,forced_nb_planes=NB_BOB_PLANES,
        palette_precision_mask=0xFF,generate_mask=True,blit_pad=True)
    plane_size = len(fsdata)//5

    for i in range(5):
        fsplane = fsdata[i*plane_size:(i+1)*plane_size]
        if any(fsplane):
            f.write(f"\t.long\tfour_barrels_bitplane_{i}\n")
            four_sprites_bitplanes.append(fsplane)
        else:
            f.write("\t.long\t0\n")
            four_sprites_bitplanes.append(None)

    f.write("\n\t.section\t.datachip\n\n")

    for i,fsplane in enumerate(four_sprites_bitplanes):
        if fsplane:
            f.write(f"four_barrels_bitplane_{i}:")
            bitplanelib.dump_asm_bytes(fsplane,f,mit_format=True)


    # sprites
    for i in range(NB_POSSIBLE_SPRITES):
        name = sprite_names[i]
        if name:
            sprite = sprites.get(i)
            for j in range(8):
                # clut is valid for this sprite
                bitmap = sprite["bitmap"]
                sprite_label = f"{name}_{j}"
                for i,bm in zip(sprite_flip_type,bitmap):
                    if bm:
                        f.write(f"{sprite_label}_{i}:")
                        bitplanelib.dump_asm_bytes(bm,f,mit_format=True)

    f.write("\n* bitplanes\n")
    # dump bitplanes
    for k,v in bitplane_cache.items():
        f.write(f"plane_{v}:")
        bitplanelib.dump_asm_bytes(k,f,mit_format=True)
