import bpy
p='/Users/justinjin/Desktop/8ball/assets/lounge/LoungeBuilder.py'
ns={'__name__':'lounge_builder','__file__':p}
exec(compile(open(p).read(),p,'exec'),ns)
ns['start_stage'](6)
