#!/usr/bin/env python3
"""Generate internal motion frames for short ball wakes. Main aura forms are real meshes."""
from pathlib import Path
import math
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
VFX=ROOT/'assets/cue/vfx/v3'

def sample(src,u,v):
    h,w=src.shape[:2]
    xx=np.clip(u*(w-1),0,w-1); yy=np.clip(v*(h-1),0,h-1)
    x=xx.astype(int);y=yy.astype(int); x1=np.minimum(x+1,w-1); y1=np.minimum(y+1,h-1)
    fx=(xx-x)[...,None];fy=(yy-y)[...,None]
    out=(src[y,x]*(1-fx)+src[y,x1]*fx)*(1-fy)+(src[y1,x]*(1-fx)+src[y1,x1]*fx)*fy
    out*=((u>=0)&(u<=1)&(v>=0)&(v<=1))[...,None]
    return out

def source(path):
    a=np.asarray(Image.open(path).convert('RGBA'),dtype=float)/255
    a[:,:,:3]*=a[:,:,3:4]
    return a

def rgba(a):
    out=a.copy();out[:,:,:3]/=np.maximum(out[:,:,3:4],1e-5)
    return Image.fromarray(np.uint8(np.clip(out,0,1)*255),'RGBA')

def trail_frames(cue,name):
    src=source(VFX/cue/name)
    y,x=np.mgrid[0:128,0:512];u=x/511;v=y/127
    out=VFX/cue/'wake_frames';out.mkdir(exist_ok=True)
    for i in range(16):
        p=math.tau*i/16
        # Local scallops curl while a molten pulse travels along the wake.
        vv=v+.055*np.sin(u*15-p*2)*np.sin(math.pi*v)
        uu=u+.018*np.sin(v*12+u*9-p)
        a=sample(src,uu,vv)
        a[:,:,:3]*=(.84+.16*np.sin(u*19-p*2))[...,None]
        rgba(a).save(out/('%02d.png'%i),optimize=True)
    return out

if __name__=='__main__':
    trail_frames('eclipse','crescent_wake_painted.png')
