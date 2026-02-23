##    int code = (m_sprite_ram[offs + 1] & 0x7f) + ((m_sprite_ram[offs + 2] & mask_bank) << shift_bits);
##    int color = (m_sprite_ram[offs + 2] & 0x0f) + 16 * m_palette_bank;
##    int flipx = m_sprite_ram[offs + 2] & 0x80;
##    int flipy = m_sprite_ram[offs + 1] & 0x80;
##    int x = (m_sprite_ram[offs + 3] + add_x + 1) & 0xFF;
##    int y = m_sprite_ram[offs];

tile={}
for i in range(0,0x10):
    tile[i] = "mario"
for i in range(0x10,0x15):
    tile[i] = "princess"
for i in range(0x15,0x1C):
    tile[i] = "barrel"
for i in range(0x1E,0x20):
    tile[i] = "hammer"
for i in range(0x20,0x38):
    tile[i] = "kong"
for i in range(0x3B,0x3D):
    tile[i] = "bouncer"
for i in range(0x3D,0x3F):
    tile[i] = "fireball"
for i in range(0x40,0x44):
    tile[i] = "flame"
tile[0x44] = "elevator"
tile[0x45] = "conveyor"
tile[0x49] = "oil_barrel"

tile[0x70] = "blank"
tile[0x3A] = "blank"

def decode(binname,name_filter=None):
    print(f"Decoding {binname}")
    with open(binname,"rb") as f:
        contents = f.read()


    for i in range(0,len(contents),4):
        block = contents[i:i+4]
        code = block[1]&0x7F
        flipy = block[1]>>7
        flipx = block[2]>>7
        color = block[2] & 0XF
        x = block[3]
        y = block[0]
        ar = (x,y,code,color,flipx,flipy)
        name = tile.get(code,"")
        if name_filter and name_filter not in name:
            continue
        if any(ar):
            raw_code_clut = block[1]*256+block[2]
            print("offset={:02}, x={}, y={}, code={:02x},name={}, code={:02x}, color={}, flipy={}".format(i,x,y,raw_code_clut,name,code,color,flipy))

decode("dkong","kong")
decode("dkong2","kong")
decode("dkong3","kong")
