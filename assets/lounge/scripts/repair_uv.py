import bpy
p='/Users/justinjin/Desktop/8ball/assets/lounge/LoungeBuilder.py'
ns={'__name__':'lounge_builder','__file__':p}
exec(compile(open(p).read(),p,'exec'),ns)
def repair():
    try:
        ns['bake_atlases'](['Furniture_A','Signs'])
        ns['export_packages']()
        ns['checkpoint'](5,render=False)
    except Exception:
        import traceback
        err=traceback.format_exc();open('/Users/justinjin/Desktop/8ball/assets/lounge/scripts/uv_repair_error.log','w').write(err)
        ns['progress'](5,'saved baked geometry checkpoint','repair_uv.py',err)
    return None
bpy.app.timers.register(repair,first_interval=3)
print('UV_REPAIR_SCHEDULED')
