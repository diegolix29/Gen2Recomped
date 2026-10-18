"""Capture a user's DS ROM through an optional Libretro DeSmuME core.

No core, ROM, firmware or capture is distributed with this tool. All core
state and a private content copy stay in --out. Never opens a user's save.
Example: python tools/ds_rom_reference.py ROM --core CORE.dll --out tmp/ref
         --frames 900 --press 300:start,500:a --shots 200,450,900
"""
import argparse
import ctypes as C
from pathlib import Path
import shutil
import numpy as np
from PIL import Image

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('rom',type=Path)
p.add_argument('--core',type=Path,required=True)
p.add_argument('--out',type=Path,required=True)
p.add_argument('--frames',type=int,default=900)
p.add_argument('--press',default='')
p.add_argument('--hold-frames',type=int,default=2,help='hold each scheduled key across both DS application ticks')
p.add_argument('--shots',default='900')
p.add_argument('--load-state',type=Path)
p.add_argument('--save-state',type=Path)
a=p.parse_args()
a.out.mkdir(parents=True,exist_ok=True)
root=str(a.out.resolve()).encode()
core=C.CDLL(str(a.core.resolve()))
class Variable(C.Structure):
    _fields_=[('key',C.c_char_p),('value',C.c_char_p)]
class GameInfo(C.Structure):
    _fields_=[('path',C.c_char_p),('data',C.c_void_p),('size',C.c_size_t),('meta',C.c_char_p)]
ENV=C.CFUNCTYPE(C.c_bool,C.c_uint,C.c_void_p)
VIDEO=C.CFUNCTYPE(None,C.c_void_p,C.c_uint,C.c_uint,C.c_size_t)
AUDIO=C.CFUNCTYPE(None,C.c_int16,C.c_int16)
BATCH=C.CFUNCTYPE(C.c_size_t,C.c_void_p,C.c_size_t)
POLL=C.CFUNCTYPE(None)
INPUT=C.CFUNCTYPE(C.c_int16,C.c_uint,C.c_uint,C.c_uint,C.c_uint)
LOG=C.CFUNCTYPE(None,C.c_int,C.c_char_p)
@LOG
def log(level,fmt): pass
defaults={}
overrides={b'desmume_cpu_mode':b'jit',b'desmume_firmware_language':b'English'}
pixel_format=0
@ENV
def environment(cmd,data):
    global pixel_format
    cmd &= ~0x10000
    if cmd in (9,30,31): C.cast(data,C.POINTER(C.c_char_p))[0]=root;return True
    if cmd==10: pixel_format=C.cast(data,C.POINTER(C.c_uint))[0];return pixel_format in (0,1,2)
    if cmd==16:
        rows=C.cast(data,C.POINTER(Variable));i=0
        while rows[i].key:
            defaults[rows[i].key]=rows[i].value.split(b'; ',1)[-1].split(b'|')[0];i+=1
        return True
    if cmd==15:
        v=C.cast(data,C.POINTER(Variable))[0]
        v.value=overrides.get(v.key,defaults.get(v.key));return bool(v.value)
    if cmd in (17,3,2,74): C.cast(data,C.POINTER(C.c_bool))[0]=cmd in (3,74);return True
    if cmd in (52,59): C.cast(data,C.POINTER(C.c_uint))[0]=0;return True
    if cmd==39: C.cast(data,C.POINTER(C.c_uint))[0]=0;return True
    if cmd==27: C.cast(data,C.POINTER(C.c_void_p))[0]=C.cast(log,C.c_void_p).value;return True
    if cmd==47: C.cast(data,C.POINTER(C.c_uint))[0]=3;return True
    if cmd==61: C.cast(data,C.POINTER(C.c_uint))[0]=1;return True
    return cmd in (1,6,8,11,18,35,37)
last=None
@VIDEO
def video(ptr,w,h,pitch):
    global last
    if ptr and ptr != C.c_void_p(-1).value:
        last=(C.string_at(ptr,pitch*h),w,h,pitch,pixel_format)
@AUDIO
def audio(left,right): pass
@BATCH
def batch(ptr,frames): return frames
@POLL
def poll(): pass
keys={'b':0,'y':1,'select':2,'start':3,'up':4,'down':5,'left':6,'right':7,'a':8,'x':9,'l':10,'r':11}
presses={}
for entry in filter(None,a.press.split(',')):
    f,key=entry.split(':')
    for held in range(max(1,a.hold_frames)): presses[int(f)+held]=keys[key]
frame=0
@INPUT
def input_state(port,device,index,key):
    return int(device==1 and key==presses.get(frame))
for name,cb in [('environment',environment),('video_refresh',video),('audio_sample',audio),
                ('audio_sample_batch',batch),('input_poll',poll),('input_state',input_state)]:
    fn=getattr(core,'retro_set_'+name);fn.argtypes=[type(cb)];fn(cb)
core.retro_init()
content=a.out/'content.nds'
if a.rom.resolve()!=content.resolve():
    shutil.copyfile(a.rom,content)
info=GameInfo(str(content.resolve()).encode(),None,0,None)
core.retro_load_game.argtypes=[C.POINTER(GameInfo)];core.retro_load_game.restype=C.c_bool
assert core.retro_load_game(C.byref(info)), 'core rejected content'
if a.load_state:
    state=a.load_state.read_bytes();buf=C.create_string_buffer(state)
    core.retro_unserialize.argtypes=[C.c_void_p,C.c_size_t];core.retro_unserialize.restype=C.c_bool
    assert core.retro_unserialize(buf,len(state)), 'state rejected'
shots=set(map(int,a.shots.split(',')))
for frame in range(1,a.frames+1):
    core.retro_run()
    if frame in shots and last:
        data,w,h,pitch,fmt=last
        if fmt==1:
            rgba=np.frombuffer(data,dtype=np.uint8).reshape(h,pitch)[:,:w*4].reshape(h,w,4)
            rgb=rgba[:,:,[2,1,0]]
        else:
            px=np.frombuffer(data,dtype='<u2').reshape(h,pitch//2)[:,:w].astype(np.uint32)
            if fmt==2: r,g,b=(px>>11)&31,(px>>5)&63,px&31;green=63
            else: r,g,b=(px>>10)&31,(px>>5)&31,px&31;green=31
            rgb=np.stack([r*255//31,g*255//green,b*255//31],axis=-1).astype(np.uint8)
        path=a.out/('frame_%05d.png'%frame)
        Image.fromarray(rgb).save(path);print('captured',path,w,h,flush=True)
    if frame%300==0: print('frame',frame,flush=True)
if a.save_state:
    core.retro_serialize_size.restype=C.c_size_t;n=core.retro_serialize_size()
    buf=C.create_string_buffer(n)
    core.retro_serialize.argtypes=[C.c_void_p,C.c_size_t];core.retro_serialize.restype=C.c_bool
    assert core.retro_serialize(buf,n)
    a.save_state.write_bytes(buf.raw)
core.retro_unload_game();core.retro_deinit()
