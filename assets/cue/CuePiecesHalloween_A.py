"""The Halloween 2026 cues of lane Cues A (2026-10-28; docs/prompts/HW_CUES_A_PROMPT.md): the
Candy Corn Cue and the Jack-o'-Lantern Cue, each drawn by its own model (a `body` piece that
replaces the shared cue mesh), plus Jack's pocket piece. See CuePieces.py for the kit and the
export; CuePiecesHalloween_B.py holds the Black Cat, Spider and Witch's Broom. Modelled in the
cue's Blender frame: X the side, Y from the tip (0) toward the butt (-7), Z up; the pocket
finisher in the pocket frame (origin at the mouth, Z up).

    candy_corn              the body: kernel tip cap, cream shaft, barber-pole wrap, orange
                            forearm, yellow handle, candy-corn bulb (brief 2.7)
    jack_o_lantern          the body: stem tip, ribbed orange shaft, spiralling vine with
                            leaves, wood collars with glowing slits, carved pumpkin butt (2.8)
    jack_o_lantern_pocket   the laughing jack-o'-lantern that rises out of the pocket (2.8)

Every body passes `check_body` before it exports (brief 2.6): the tip ends at the pivot and
stays thin, the hand zones keep the envelope, the rest stays inside the clearances, and
nothing but an Aim-fade joint reaches further than 0.3 studs past the butt.
"""
import math

from CuePieces import piece, apply_modifier  # noqa: F401  (apply_modifier for the builders to come)

# The modelling rules (brief 2.6; the same numbers as Cues B's brief 2.2 and Config.CueSkins.Bodies).
LENGTH = 7.0                 # Config.Cue.CueLengthStuds
TIP_SLACK = 0.01             # a body must reach this close to the pivot (Bodies.TipSlackStuds)
TIP_ACROSS = 0.12            # at most this across for the first TIP_LEN studs (the ball's radius is 0.18)
TIP_LEN = 0.3
HAND_ZONES = ((0.3, 2.1), (4.4, 6.75))   # bridge hand, grip hand: envelope +-HAND_TOL, centred
HAND_TOL = 0.02
SIDE_EXTRA = 0.08            # up to 6.75: at most envelope + this sideways and downward
UP_EXTRA = 0.25              # +Z between the hand zones (2.1 to 4.4): leaves, rings, kernels
BUTT_FROM, BUTT_EXTRA = 6.75, 0.2   # from 6.75 to the butt: the bulb, the pumpkin
PAST_BUTT = 0.3              # past the butt (Bodies.PastButtStuds)
AIM_OVERHANG = 1.5           # an Aim-fade joint's reach past the butt (Bodies.MaxOverhangStuds)
MAX_PARTS, MAX_TRIS = 8, 10000   # the hard budget (the data tool stops over it); aim at 6 and 6,000


def envelope():
    """The cue's radius at distance d from the tip (Shape.json's envelope, CueShape.radiusAt)."""
    import cue_common as cc
    return cc.Envelope(cc.load_shape()[0])


def _bins(kit, step=0.1):
    """Every vertex of the kit (world, Blender cue frame) by 0.1-stud bin of its distance from
    the tip: bin -> [(d, x, z, joint, aim)]."""
    out = {}
    for jname, j in kit.joints.items():
        aim = bool(j.get('Aim'))
        for ob in j['objects']:
            M = ob.matrix_world
            for v in ob.data.vertices:
                p = M @ v.co
                d = -p.y
                out.setdefault(int(math.floor(d / step)), []).append((d, p.x, p.z, jname, aim))
    return out


def check_body(kit, step=0.1):
    """Assert the body obeys brief 2.6, sampling every `step` studs; raise with the first few
    problems so a bad body never exports. Checks: a vertex at the pivot (the tip reaches), the
    tip thin, the hand zones at the envelope and centred, side and down clearance up to 6.75,
    the +Z allowance between the hands, the butt allowance, the past-butt limits (Aim joints
    excepted up to AIM_OVERHANG), and nothing before the tip."""
    R = envelope()
    bins = _bins(kit, step)
    problems = []
    all_d = [v[0] for vs in bins.values() for v in vs]
    if not all_d:
        raise AssertionError('%s: no vertices' % kit.pid)
    if min(all_d) > TIP_SLACK:
        problems.append('the tip stops %.3f studs short of the pivot (at most %.2f)' % (min(all_d), TIP_SLACK))
    if min(all_d) < -TIP_SLACK:
        problems.append('a part reaches %.3f studs before the tip' % -min(all_d))
    for b in sorted(bins):
        vs = bins[b]
        d0 = max(0.0, b * step)
        r_env = R(min(d0 + step / 2, LENGTH))
        rs = [math.hypot(x, z) for _, x, z, _, _ in vs]
        r_max = max(rs)
        # the widest vertex of the bin, by direction
        r_side = max((math.hypot(x, z) for _, x, z, _, _ in vs if z <= 0 or abs(x) > abs(z)), default=0.0)
        r_up = max((math.hypot(x, z) for _, x, z, _, _ in vs if z > 0 and abs(z) >= abs(x)), default=0.0)
        if d0 < TIP_LEN:
            if 2 * r_max > TIP_ACROSS + 1e-6:
                problems.append('%.1f: %.3f across at the tip (at most %.2f)' % (d0, 2 * r_max, TIP_ACROSS))
            continue
        past = d0 - LENGTH
        if past >= 0:
            far = [(d, j, a) for d, _, _, j, a in vs if d > LENGTH + PAST_BUTT and not a]
            if far:
                d, j, _ = max(far)
                problems.append('%s reaches %.2f studs past the butt (at most %.2f without "Aim": "fade")' % (j, d - LENGTH, PAST_BUTT))
            far_aim = [(d, j) for d, _, _, j, a in vs if d > LENGTH + AIM_OVERHANG and a]
            if far_aim:
                d, j = max(far_aim)
                problems.append('%s (Aim) reaches %.2f studs past the butt (at most %.2f)' % (j, d - LENGTH, AIM_OVERHANG))
            continue
        in_hand = any(a <= d0 < b_ for a, b_ in HAND_ZONES)
        if in_hand:
            if r_max > r_env + HAND_TOL + 1e-6:
                problems.append('%.1f (hand zone): radius %.3f, envelope %.3f (+%.2f at most)' % (d0, r_max, r_env, HAND_TOL))
            if r_max < r_env - HAND_TOL - 1e-6:
                problems.append('%.1f (hand zone): radius %.3f, envelope %.3f (the hand would sink in)' % (d0, r_max, r_env))
            # centred: the outer vertices' mean sits on the axis
            outer = [(x, z) for _, x, z, _, _ in vs if math.hypot(x, z) >= r_max - 0.02]
            cx = sum(x for x, _ in outer) / len(outer)
            cz = sum(z for _, z in outer) / len(outer)
            if math.hypot(cx, cz) > HAND_TOL + 1e-6:
                problems.append('%.1f (hand zone): centreline off by %.3f' % (d0, math.hypot(cx, cz)))
            continue
        if d0 >= BUTT_FROM:
            if r_max > r_env + BUTT_EXTRA + 1e-6:
                problems.append('%.1f (butt): radius %.3f, envelope %.3f (+%.2f at most)' % (d0, r_max, r_env, BUTT_EXTRA))
            continue
        if r_side > r_env + SIDE_EXTRA + 1e-6:
            problems.append('%.1f: radius %.3f sideways or down, envelope %.3f (+%.2f at most)' % (d0, r_side, r_env, SIDE_EXTRA))
        up_allow = UP_EXTRA if 2.1 <= d0 < 4.4 else SIDE_EXTRA
        if r_up > r_env + up_allow + 1e-6:
            problems.append('%.1f: radius %.3f on +Z, envelope %.3f (+%.2f at most)' % (d0, r_up, r_env, up_allow))
    n_parts = sum(len({m.material for m in ob.material_slots}) for j in kit.joints.values() for ob in j['objects'])
    if n_parts > MAX_PARTS:
        problems.append('about %d parts (joint x material), at most %d' % (n_parts, MAX_PARTS))
    if problems:
        raise AssertionError('%s fails the body rules:\n  ' % kit.pid + '\n  '.join(problems[:12]))
    print('CUE pieces %s: body rules pass' % kit.pid)
