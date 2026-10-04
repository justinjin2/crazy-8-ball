#!/usr/bin/env python3
"""Beta's exact drafting sprites. Geometry lives in CuePiecesUnique; no black panel backgrounds."""
from pathlib import Path
import math
from PIL import Image, ImageDraw

OUT=Path(__file__).resolve().parents[1]/'assets/cue/vfx/v3/beta'
OUT.mkdir(parents=True,exist_ok=True)
S=2

def line(draw,points,color,width):
    draw.line([(round(x*S),round(y*S)) for x,y in points],fill=color,width=max(1,round(width*S)),joint='curve')

def arc(draw,c,r,a,b,col,w):
    n=max(6,int((b-a)/3))
    line(draw,[(c[0]+r*math.cos(math.radians(a+(b-a)*i/n)),c[1]+r*math.sin(math.radians(a+(b-a)*i/n))) for i in range(n+1)],col,w)

def save(im,name,size):
    im.resize(size,Image.Resampling.LANCZOS).save(OUT/name)

# Broad luminous wire strokes survive a 0.6-stud trail on a phone. Three sections
# read as drafted volume without turning into subpixel grey lines over bright felt.
im=Image.new('RGBA',(1024*S,256*S));d=ImageDraw.Draw(im)
for x in (220,510,810):
    alpha=int(255*(.65+.35*x/1024))
    points=[(x+58*math.cos(t*math.tau/64),128+84*math.sin(t*math.tau/64)) for t in range(65)]
    line(d,points,(0,102,255,alpha),22)
    line(d,points,(125,244,255,alpha),12)
for y in (44,212):
    line(d,[(30,y),(990,y)],(0,91,255,240),22)
    line(d,[(30,y),(990,y)],(137,250,255,255),11)
line(d,[(30,128),(990,128)],(116,12,221,240),24)
line(d,[(30,128),(990,128)],(255,126,247,255),12)
save(im,'wire_wake.png',(1024,256))
im=Image.new('RGBA',(1024*S,1024*S));d=ImageDraw.Draw(im)
for r,w in ((354,8),(402,4)):
    for j in range(4): arc(d,(512,512),r,j*90+7,j*90+79,(255,255,255,255),w)
for j in range(32):
    t=math.tau*j/32
    line(d,[(512+math.cos(t)*r,512+math.sin(t)*r) for r in (416,444 if j%4==0 else 429)],(255,255,255,235),6)
for j in range(4):
    t=math.tau*j/4
    line(d,[(512+math.cos(t)*r,512+math.sin(t)*r) for r in (275,390)],(255,255,255,255),7)
save(im,'draft_ring.png',(1024,1024))
im=Image.new('RGBA',(256*S,256*S));d=ImageDraw.Draw(im)
line(d,[(68,45),(45,45),(45,105)],(255,255,255,255),12)
line(d,[(188,211),(211,211),(211,151)],(255,255,255,255),12)
line(d,[(110,128),(146,128)],(255,255,255,255),9)
line(d,[(128,110),(128,146)],(255,255,255,255),9)
save(im,'registration.png',(256,256))
print('Wrote 3 Beta drafting sprites')
