import subprocess,os,struct,glob,tempfile
import shutil

sox = "sox"
gamename = "dkong"
module_name = "donkey_kong"

if not shutil.which("sox"):
    raise Exception("sox command not in path, please install it")
# BTW convert wav to mp3: ffmpeg -i input.wav -codec:a libmp3lame -b:a 330k output.mp3

#wav_files = glob.glob("sounds/*.wav")

this_dir = os.path.dirname(__file__)
sound_dir = os.path.join(this_dir,"..","sounds")

this_dir = os.path.dirname(__file__)
src_dir = os.path.join(this_dir,"../../src/amiga")
outfile = os.path.join(src_dir,"sounds.68k")
sndfile = os.path.join(src_dir,"sound_entries.68k")

vhq_sample_rate = 22050
hq_sample_rate = 16000
lq_sample_rate = 11025

music_volume = 26

EMPTY_SND = "EMPTY_SND"
sound_dict = {
# samples
"BOOM_SND"             :{"index":0x10,"channel":1,"sample_rate":lq_sample_rate,"priority":1},
"CREDIT_SND"             :{"index":0x11,"channel":1,"sample_rate":hq_sample_rate,"priority":1},
"DEAD_TUNE_SND"             :{"index":0x12,"pattern":0xE,"loops":False,"volume":music_volume+10,"ticks":150},
"JUMPED_OVER_SND"             :{"index":0x13,"channel":1,"sample_rate":hq_sample_rate,"priority":1},
"KILL_ENEMY_SND"             :{"index":0x14,"channel":1,"sample_rate":hq_sample_rate,"priority":1},
"START_SND"             :{"index":0x15,"channel":1,"sample_rate":lq_sample_rate,"priority":1},
"JUMPING_SND"             :{"index":0x16,"channel":2,"sample_rate":vhq_sample_rate,"priority":1},
"WALKING_SND"             :{"index":0x17,"channel":2,"sample_rate":hq_sample_rate,"priority":1},
"BOUNCER_FALLS_SND"             :{"index":0x18,"channel":3,"sample_rate":hq_sample_rate,"priority":1},
"BOUNCER_BOUNCES_SND"             :{"index":0x19,"channel":0,"sample_rate":hq_sample_rate,"priority":1},  # no music in level 3
"GORILLA_YELLS_SND"       :{"index":0xF,"channel":3,"sample_rate":hq_sample_rate,"priority":1},  # also matches MUS define

# tunes match the MUS defines in donkey_kong.68k source
"START_TUNE_SND"              :{"index":1,"pattern":1,"loops":False,"volume":40,"ticks":250},
"LEVEL_TUNE_SND"              :{"index":2,"pattern":2,"loops":False,"volume":32,"ticks":150},
"OUT_OF_TIME_TUNE_SND"              :{"index":3,"pattern":0xC,"loops":True,"volume":music_volume},
"HAMMER_TUNE_SND"              :{"index":4,"pattern":3,"loops":True,"volume":music_volume},
"END_SCREEN_TUNE_SND"              :{"index":7,"pattern":5,"loops":False,"volume":40,"ticks":95},
"END_LEVEL_1_TUNE_SND"              :{"index":0xC,"pattern":6,"loops":False,"volume":music_volume+10},
"END_LEVEL_2_TUNE_SND"              :{"index":0x5,"pattern":8,"loops":False,"volume":music_volume+10},
"PIE_FACTORY_TUNE_SND"              :{"index":9,"pattern":4,"loops":True,"volume":music_volume},
"GIRDERS_TUNE_SND"                 :{"index":8,"pattern":10,"loops":True,"volume":music_volume},
"RIVET_TUNE_SND"                    :{"index":0xb,"pattern":0xB,"loops":True,"volume":music_volume},
"DK_FALLS_TUNE_SND"              :{"index":0XE,"pattern":0xD,"loops":False,"volume":music_volume+10,"ticks":155},

}

max_sound = max(x["index"] for x in sound_dict.values())+1
sound_table = [""]*max_sound
sound_table_set = ["\t.long\t0,0"]*max_sound



snd_header = rf"""
# sound tables
#
# the "sound_table" table has 8 bytes per entry
# first word: 0: no entry, 1: sample, 2: pattern from music module
# second word: 0 except for music module: pattern number
# longword: sample data pointer if sample, 0 if no entry and
# 2 words: 0/1 noloop/loop followed by duration in ticks
#
FXFREQBASE = 3579564
HQ_SOUNDFREQ = {hq_sample_rate}

    .macro    SOUND_ENTRY    sound_name,size,channel,soundfreq,volume,priority
\sound_name\()_sound:
    .long    \sound_name\()_raw
    .word   \size
    .word   FXFREQBASE/\soundfreq,\volume
    .byte    \channel
    .byte    \priority
    .endm

"""

def write_asm(contents,fw):
    n=0
    for c in contents:
        if n%16 == 0:
            fw.write("\n\t.byte\t0x{:x}".format(c))
        else:
            fw.write(",0x{:x}".format(c))
        n += 1
    fw.write("\n")

music_module_label = f"{gamename}_tunes"

raw_file = os.path.join(tempfile.gettempdir(),"out.raw")
with open(sndfile,"w") as fst,open(outfile,"w") as fw:
    fst.write(snd_header)

    fw.write("\t.section\t.datachip\n")
    fw.write("\t.global\t{}\n".format(music_module_label))

    # make sure next section will be aligned
    with open(os.path.join(sound_dir,f"{module_name}_conv.mod"),"rb") as f:
        contents = f.read()
    fw.write("{}:".format(music_module_label))
    write_asm(contents,fw)
    fw.write("\t.align\t8\n")

    for wav_file,details in sound_dict.items():
        wav_name = os.path.basename(wav_file).lower()[:-4]
        if details.get("channel") is not None:
            fw.write("\t.global\t{}_raw\n".format(wav_name))


    for wav_entry,details in sound_dict.items():
        sound_index = details["index"]
        channel = details.get("channel")
        if channel is None:
            # if music loops, ticks are set to 1 so sound orders only can happen once (else music is started 50 times per second!!)

            sound_table_set[sound_index] = "\t.word\t{},{},{}\n\t.byte\t{},{}".format(2,details["pattern"],details.get("ticks",0),details["volume"],int(details["loops"]))
        else:
            wav_name = os.path.basename(wav_entry).lower()[:-4]
            wav_file = os.path.join(sound_dir,wav_name+".wav")

            def get_sox_cmd(sr,output):
                return [sox,"--volume","0.92",wav_file,"--channels","1","--bits","8","-r",str(sr),"--encoding","signed-integer",output]


            used_sampling_rate = details["sample_rate"]
            used_priority = details.get("priority",1)

            cmd = get_sox_cmd(used_sampling_rate,raw_file)
            print(f"Processing {wav_name}...")
            subprocess.check_call(cmd)
            with open(raw_file,"rb") as f:
                contents = f.read()

            # compute max amplitude so we can feed the sound chip with an amped sound sample
            # and reduce the replay volume. this gives better sound quality than replaying at max volume
            # (thanks no9 for the tip!)
            signed_data = [x if x < 128 else x-256 for x in contents]
            maxsigned = max(signed_data)
            minsigned = min(signed_data)

            amp_ratio = max(maxsigned,abs(minsigned))/127

            wav = os.path.splitext(wav_name)[0]
            volume = int(64*amp_ratio)
            # for this game I'm sticking all sounds to the max

            sound_table[sound_index] = "    SOUND_ENTRY {},{},{},{},{},{}\n".format(wav,len(signed_data)//2,channel,used_sampling_rate,volume,used_priority)
            sound_table_set[sound_index] = f"\t.word\t1,{int(details.get('loops',0))}\n\t.long\t{wav}_sound"

            if amp_ratio > 0:
                maxed_contents = [int(x/amp_ratio) for x in signed_data]
            else:
                maxed_contents = signed_data

            print("{}: ratio: {}, min: {}/128, max: {}/127".format(wav_name,amp_ratio,
                                                    min(maxed_contents),max(maxed_contents)))

            signed_contents = bytes([x if x >= 0 else 256+x for x in maxed_contents])

            # pre-pad with 0W, used by ptplayer for idling
            if signed_contents[0] != b'\x00' and signed_contents[1] != b'\x00':
                # add zeroes
                signed_contents = struct.pack(">H",0) + signed_contents

            contents = signed_contents
            # align on 16-bit
            if len(contents)%2:
                contents += b'\x00'
            # pre-pad with 0W, used by ptplayer for idling
            if contents[0] != b'\x00' and contents[1] != b'\x00':
                # add zeroes
                contents = b'\x00\x00' + contents

            fw.write("{}_raw:   | {} bytes".format(wav,len(contents)))

            if len(contents)>65530:
                raise Exception(f"Sound {wav_entry} is too long")
            write_asm(contents,fw)



    fst.writelines(sound_table)
    fst.write("\n\t.global\t{0}\n\n{0}:\n".format("sound_table"))
    for i,st in enumerate(sound_table_set):
        fst.write(st)
        fst.write(" | {}\n\n".format(i))



