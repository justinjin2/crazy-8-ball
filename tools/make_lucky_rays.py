# Generates the transparent, smoothly faded lucky-block reveal rays.
# Run from the repository root; upload assets/ui/lucky-rays.png using roblox_upload.py.
from PIL import Image
from math import atan2,cos,hypot,pi
size=1024
im=Image.new('RGBA',(size,size))
pixels=im.load()
for y in range(size):
 for x in range(size):
  dx=(x+.5-size/2)/(size/2);dy=(y+.5-size/2)/(size/2)
  r=hypot(dx,dy)
  angular=max(0,cos(atan2(dy,dx)*18))**1.5
  radial=max(0,1-r*r)**2
  center=min(1,r/.08)
  alpha=round(255*angular*radial*center)
  pixels[x,y]=(255,255,255,alpha)
im.save('assets/ui/lucky-rays.png')
