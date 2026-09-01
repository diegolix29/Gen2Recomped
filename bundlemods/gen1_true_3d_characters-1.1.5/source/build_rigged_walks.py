import os, re, math, json, shutil, zipfile, time
from pathlib import Path
import numpy as np

SRC_ROOT=Path('/mnt/data/misc_src/Miscellaneous NPCs')
BASE=Path('/mnt/data/gen1chars102')
OUT=Path('/mnt/data/Gen1True3DCharacters_v1.1.0')
ZIP=Path('/mnt/data/Gen1True3DCharacters_Gen1Recomp-v1.1.0.zip')
ASSETS=OUT/'assets'

MODELS={
    'adult_man':      ('Adults/Man', 'tr0061_00_adultm.smd', 24.0),
    'adult_woman':    ('Adults/Woman', 'tr0063_00_adultf.smd', 24.0),
    'cook':           ('Cook', 'tr0088_00_cook.smd', 24.0),
    'elderly_man':    ('Elderly/Man', 'tr0064_00_oldm.smd', 23.0),
    'elderly_woman':  ('Elderly/Woman', 'tr0065_00_oldf.smd', 23.0),
    'fat':            ('Fat', 'tr0066_00_fat.smd', 24.0),
    'guard':          ('Guard', 'tr0075_00_guard.smd', 24.0),
    'juvenile_boy':   ('Juveniles/Boy', 'tr0083_00_juvenilem.smd', 20.0),
    'juvenile_girl':  ('Juveniles/Girl', 'tr0084_00_juveniles.smd', 20.0),
    'kid_boy':        ('Kids/Boy', 'tr0057_00_childm.smd', 17.0),
    'kid_girl':       ('Kids/Girl', 'tr0058_00_childf.smd', 17.0),
    'middle_man':     ('Middle Aged/Man', 'tr0067_00_middlem.smd', 24.0),
    'middle_woman':   ('Middle Aged/Woman', 'tr0068_00_middlef.smd', 24.0),
    'muscle':         ('Muscle', 'tr0062_00_muscle.smd', 25.0),
    'scientist':      ('Scientist', 'tr0086_00_nresearcher.smd', 24.0),
    'staff_man':      ('Staff/Man', 'tr0079_00_staffm.smd', 24.0),
    'staff_woman':    ('Staff/Woman', 'tr0080_00_stafff.smd', 24.0),
    'young_boy':      ('Youngsters/Boy', 'tr0059_00_youngm.smd', 22.0),
    'young_girl':     ('Youngsters/Girl', 'tr0060_00_youngf.smd', 22.0),
}

WALK_FRAMES=12
ATLAS=2048
PLACEMENTS={
    'body': (0,0,1024,1024),
    'eye': (1024,0,1024,1024),
    'skin': (0,1024,512,1024),
    'hair': (512,1024,512,512),
}
LIGHT=np.array([0.42,0.76,0.49],dtype=np.float64); LIGHT/=np.linalg.norm(LIGHT)

RESUME=os.environ.get('RESUME')=='1'
FINALIZE=os.environ.get('FINALIZE')=='1'
if not RESUME:
    if OUT.exists(): shutil.rmtree(OUT)
    shutil.copytree(BASE,OUT)


def descendants(parents,root):
    out={root}; changed=True
    while changed:
        changed=False
        for b,p in parents.items():
            if p in out and b not in out:
                out.add(b); changed=True
    return out


def parse_smd(path):
    lines=path.read_text(errors='replace').splitlines()
    names={}; parents={}
    i=lines.index('nodes')+1
    while lines[i].strip()!='end':
        m=re.match(r'(\d+) "(.*)" (-?\d+)',lines[i])
        if m:
            b=int(m.group(1)); names[b]=m.group(2); parents[b]=int(m.group(3))
        i+=1
    tris=[]
    i=lines.index('triangles')+1
    while i<len(lines) and lines[i].strip()!='end':
        mat=lines[i].strip(); i+=1
        vs=[]
        for _ in range(3):
            p=lines[i].split(); i+=1
            bone=int(p[0]); pos=np.array(list(map(float,p[1:4])),dtype=np.float64)
            normal=np.array(list(map(float,p[4:7])),dtype=np.float64)
            uv=np.array(list(map(float,p[7:9])),dtype=np.float64)
            links=[]
            if len(p)>9:
                n=int(p[9]); j=10
                for _k in range(n): links.append((int(p[j]),float(p[j+1]))); j+=2
            if not links: links=[(bone,1.0)]
            vs.append((pos,normal,uv,links))
        tris.append((mat,vs))
    return names,parents,tris


def rotx(v,a):
    c,s=math.cos(a),math.sin(a)
    return np.array([v[0],c*v[1]-s*v[2],s*v[1]+c*v[2]],dtype=np.float64)

def rotz(v,a):
    c,s=math.cos(a),math.sin(a)
    return np.array([c*v[0]-s*v[1],s*v[0]+c*v[1],v[2]],dtype=np.float64)

def rx_about(p,pivot,a): return rotx(p-pivot,a)+pivot

def rz_about(p,pivot,a): return rotz(p-pivot,a)+pivot


def weighted_points(tris,group,min_w=0.16):
    pts=[]
    for _mat,vs in tris:
        for pos,_n,_uv,links in vs:
            w=sum(w for b,w in links if b in group)
            if w>=min_w: pts.append(pos)
    if not pts: return np.zeros((0,3))
    return np.array(pts,dtype=np.float64)


def arm_joint(tris,group,side):
    pts=weighted_points(tris,group)
    if len(pts)==0: return np.zeros(3)
    xs=pts[:,0]
    # In these models +X is anatomical left. Choose the torso-side edge.
    if side=='L':
        cut=np.quantile(xs,0.10); near=pts[xs<=cut]
    else:
        cut=np.quantile(xs,0.90); near=pts[xs>=cut]
    if len(near)<6: near=pts
    return np.median(near,axis=0)


def leg_joint(tris,group):
    pts=weighted_points(tris,group)
    if len(pts)==0: return np.zeros(3)
    ys=pts[:,1]
    cut=np.quantile(ys,0.90)
    near=pts[ys>=cut]
    if len(near)<6: near=pts
    return np.median(near,axis=0)


def groups_and_pivots(names,parents,tris):
    by={name:i for i,name in names.items()}
    def gid(name):
        if name not in by: raise KeyError(name)
        return by[name]
    g={}
    for side in ('L','R'):
        g[side+'ARM']=descendants(parents,gid(side+'Arm'))
        g[side+'FORE']=descendants(parents,gid(side+'ForeArm'))
        g[side+'HAND']=descendants(parents,gid(side+'Hand'))
        g[side+'THIGH']=descendants(parents,gid(side+'Thigh'))
        g[side+'LEG']=descendants(parents,gid(side+'Leg'))
        g[side+'FOOT']=descendants(parents,gid(side+'Foot'))
    piv={
        'LSHOULDER':arm_joint(tris,g['LARM'],'L'),
        'LELBOW':arm_joint(tris,g['LFORE'],'L'),
        'LWRIST':arm_joint(tris,g['LHAND'],'L'),
        'RSHOULDER':arm_joint(tris,g['RARM'],'R'),
        'RELBOW':arm_joint(tris,g['RFORE'],'R'),
        'RWRIST':arm_joint(tris,g['RHAND'],'R'),
        'LHIP':leg_joint(tris,g['LTHIGH']),
        'LKNEE':leg_joint(tris,g['LLEG']),
        'LANKLE':leg_joint(tris,g['LFOOT']),
        'RHIP':leg_joint(tris,g['RTHIGH']),
        'RKNEE':leg_joint(tris,g['RLEG']),
        'RANKLE':leg_joint(tris,g['RFOOT']),
    }
    return g,piv


def arm_chain_point(p,side,piv,base,swing,elbow=0,wrist=0,level=1):
    sh=piv[side+'SHOULDER']; el=piv[side+'ELBOW']; wr=piv[side+'WRIST']
    q=rz_about(p,sh,base); q=rx_about(q,sh,swing)
    if level>=2:
        e=rz_about(el,sh,base); e=rx_about(e,sh,swing)
        q=rx_about(q,e,elbow)
    if level>=3:
        e=rz_about(el,sh,base); e=rx_about(e,sh,swing)
        w=rz_about(wr,sh,base); w=rx_about(w,sh,swing); w=rx_about(w,e,elbow)
        q=rx_about(q,w,wrist)
    return q


def arm_chain_normal(n,base,swing,elbow=0,wrist=0,level=1):
    q=rotz(n,base); q=rotx(q,swing)
    if level>=2: q=rotx(q,elbow)
    if level>=3: q=rotx(q,wrist)
    return q


def leg_chain_point(p,side,piv,hip,knee=0,ankle=0,level=1):
    hp=piv[side+'HIP']; kn=piv[side+'KNEE']; an=piv[side+'ANKLE']
    q=rx_about(p,hp,hip)
    if level>=2:
        k=rx_about(kn,hp,hip); q=rx_about(q,k,knee)
    if level>=3:
        k=rx_about(kn,hp,hip)
        a=rx_about(an,hp,hip); a=rx_about(a,k,knee)
        q=rx_about(q,a,ankle)
    return q


def leg_chain_normal(n,hip,knee=0,ankle=0,level=1):
    q=rotx(n,hip)
    if level>=2: q=rotx(q,knee)
    if level>=3: q=rotx(q,ankle)
    return q


def pose_params(theta=None):
    # Neutral standing rig. Arms are brought down from the source T pose and
    # elbows/wrists get a small relaxed bend instead of hanging rigidly.
    if theta is None:
        return dict(armL=0,armR=0,elL=math.radians(8),elR=math.radians(8),
                    wrL=math.radians(-3),wrR=math.radians(-3),
                    hipL=0,hipR=0,kneeL=0,kneeR=0,ankleL=0,ankleR=0)
    s=math.sin(theta)
    # Opposed arm/leg swing, modest enough for tiny overworld models.
    arm=math.radians(18)*s
    hip=math.radians(23)*s
    # Knee flex peaks during each leg's swing phase and never hyperextends.
    bendL=math.radians(6 + 24*(0.5+0.5*math.sin(theta-math.pi/2)))
    bendR=math.radians(6 + 24*(0.5+0.5*math.sin(theta+math.pi/2)))
    return dict(
        armL=-arm, armR=arm,
        elL=math.radians(9)+math.radians(3)*(0.5+0.5*math.sin(theta+0.4)),
        elR=math.radians(9)+math.radians(3)*(0.5+0.5*math.sin(theta+math.pi+0.4)),
        wrL=math.radians(-3), wrR=math.radians(-3),
        hipL=hip, hipR=-hip,
        kneeL=bendL, kneeR=bendR,
        ankleL=-bendL*0.28-math.radians(3)*s,
        ankleR=-bendR*0.28+math.radians(3)*s,
    )


def pose_vertex(pos,n,links,g,piv,params):
    # One full transform per bone influence, then linear blend skinning using
    # the original SMD weights. This keeps shoulders/elbows/knees continuous
    # instead of cutting the model into rigid pieces.
    pp=np.zeros(3,dtype=np.float64); nn=np.zeros(3,dtype=np.float64); total=0.0
    for b,w in links:
        p=pos.copy(); qn=n.copy()
        if b in g['LARM']:
            level=3 if b in g['LHAND'] else (2 if b in g['LFORE'] else 1)
            p=arm_chain_point(p,'L',piv,math.radians(-78),params['armL'],params['elL'],params['wrL'],level)
            qn=arm_chain_normal(qn,math.radians(-78),params['armL'],params['elL'],params['wrL'],level)
        elif b in g['RARM']:
            level=3 if b in g['RHAND'] else (2 if b in g['RFORE'] else 1)
            p=arm_chain_point(p,'R',piv,math.radians(78),params['armR'],params['elR'],params['wrR'],level)
            qn=arm_chain_normal(qn,math.radians(78),params['armR'],params['elR'],params['wrR'],level)
        elif b in g['LTHIGH']:
            level=3 if b in g['LFOOT'] else (2 if b in g['LLEG'] else 1)
            p=leg_chain_point(p,'L',piv,params['hipL'],params['kneeL'],params['ankleL'],level)
            qn=leg_chain_normal(qn,params['hipL'],params['kneeL'],params['ankleL'],level)
        elif b in g['RTHIGH']:
            level=3 if b in g['RFOOT'] else (2 if b in g['RLEG'] else 1)
            p=leg_chain_point(p,'R',piv,params['hipR'],params['kneeR'],params['ankleR'],level)
            qn=leg_chain_normal(qn,params['hipR'],params['kneeR'],params['ankleR'],level)
        pp += w*p; nn += w*qn; total += w
    if total < 0.999:
        # SMD weights normally sum to 1, but preserve any implicit remainder.
        pp += (1-total)*pos; nn += (1-total)*n
    ln=np.linalg.norm(nn)
    if ln>1e-10: nn/=ln
    return pp,nn


def pose_mesh(tris,g,piv,params):
    out=[]
    for mat,vs in tris:
        pvs=[]
        for pos,n,uv,links in vs:
            p,nn=pose_vertex(pos,n,links,g,piv,params)
            pvs.append((p,nn,uv))
        out.append((mat,pvs))
    return out


def atlas_uv(mat,uv):
    base=mat.split('.')[0]
    x,y,w,h=PLACEMENTS[base]
    u=float(uv[0])%1.0; v=float(uv[1])%1.0
    return (x+u*w)/ATLAS, (y+(1.0-v)*h)/ATLAS


def write_mesh(path,posed,S,cx,cz,ground_y,comment):
    def q(x): return round(float(x),6)
    vertices=[]; indices=[]; lookup={}
    for mat,vs in posed:
        for p,n,uv in vs:
            x=(p[0]-cx)*S+8.0; y=(p[1]-ground_y)*S; z=(p[2]-cz)*S
            u,v=atlas_uv(mat,uv)
            diffuse=max(0.0,float(np.dot(n,LIGHT))); sh=0.78+0.22*diffuse
            k=(q(x),q(y),q(z),q(u),q(v),q(sh))
            idx=lookup.get(k)
            if idx is None:
                idx=len(vertices)+1; lookup[k]=idx; vertices.append(k)
            indices.append(idx)
    with open(path,'w',encoding='utf-8',newline='\n') as f:
        f.write('-- '+comment+'\nreturn {\n  vertices = {\n')
        for x,y,z,u,v,sh in vertices:
            f.write(f'    {{{x:.6f},{y:.6f},{z:.6f},{u:.6f},{v:.6f},{sh:.6f}}},\n')
        f.write('  },\n  indices = {\n    ')
        for j,idx in enumerate(indices):
            if j and j%36==0: f.write('\n    ')
            f.write(str(idx))
            if j!=len(indices)-1: f.write(',')
        f.write('\n  }\n}\n')
    return len(vertices),len(indices)//3


def build_model(key,rel,smd_name,target_h):
    t0=time.time(); path=SRC_ROOT/rel/smd_name
    names,parents,tris=parse_smd(path); g,piv=groups_and_pivots(names,parents,tris)
    neutral=pose_mesh(tris,g,piv,pose_params(None))
    alln=np.array([p for _m,vs in neutral for p,_n,_uv in vs])
    mn=alln.min(0); mx=alln.max(0); S=target_h/(mx[1]-mn[1]); cx=(mn[0]+mx[0])/2; cz=(mn[2]+mx[2])/2
    v,t=write_mesh(ASSETS/f'{key}_mesh.lua',neutral,S,cx,cz,mn[1],f'Rigged neutral pose for {key}.')
    for fi in range(WALK_FRAMES):
        theta=2*math.pi*fi/WALK_FRAMES
        posed=pose_mesh(tris,g,piv,pose_params(theta))
        fp=np.array([p for _m,vs in posed for p,_n,_uv in vs])
        # Anchor the lowest foot/sole to the floor each frame. Keeping neutral
        # X/Z centering avoids the model sliding sideways as limbs swing.
        ground=fp[:,1].min()
        write_mesh(ASSETS/f'{key}_walk_{fi+1:02d}.lua',posed,S,cx,cz,ground,
                   f'Rigged walk frame {fi+1}/{WALK_FRAMES} for {key}.')
    print(f'{key}: {v} verts {t} tris, {time.time()-t0:.1f}s', flush=True)

selected=os.environ.get('MODEL_KEYS')
selected=set(selected.split(',')) if selected else set(MODELS)
for key,(rel,smd,h) in MODELS.items():
    if key in selected:
        build_model(key,rel,smd,h)

if not FINALIZE:
    raise SystemExit(0)

# Patch main.lua for lazy per-frame walking meshes.
main_path=OUT/'main.lua'
main=main_path.read_text(encoding='utf-8')
main=main.replace('-- Gen1 TRUE 3D Characters v1.0.1','-- Gen1 TRUE 3D Characters v1.1.0')
# Add walk metadata to every generic model definition.
for key in MODELS:
    # Locate the line containing this definition and inject metadata before }
    pat=re.compile(rf'({re.escape(key)}\s*=\s*\{{[^\n]+texPath="assets/{re.escape(key)}_atlas\.png")("\s*\}})')
    main,n=pat.subn(rf'\1", walkPrefix="assets/{key}_walk_", walkFrames={WALK_FRAMES} }}',main)
    if n==0:
        print('WARN no model line patch for',key)

old='''  local function ensureGeneric(key)\n    local info = MODEL_DEFS[key]\n    if not info then return false end\n    if info.mesh and info.texture then return true end\n    if info.failed then return false end\n\n    local data, err = readMeshData(info.meshPath)\n    if not data then\n      mod.log:error("%s mesh load failed: %s", key, tostring(err))\n      info.failed = true\n      return false\n    end\n    info.mesh = Voxel3D.newMesh(data.vertices or {}, data.indices or {})\n    info.texture = loadTexture(info.texPath)\n    if not (info.mesh and info.texture) then\n      mod.log:error("%s GPU model creation failed", key)\n      info.failed = true\n      return false\n    end\n    data.vertices, data.indices = nil, nil\n    collectgarbage("step")\n    return true\n  end\n'''
new='''  local function ensureGeneric(key)\n    local info = MODEL_DEFS[key]\n    if not info then return false end\n    if info.mesh and info.texture then return true end\n    if info.failed then return false end\n\n    local data, err = readMeshData(info.meshPath)\n    if not data then\n      mod.log:error("%s mesh load failed: %s", key, tostring(err))\n      info.failed = true\n      return false\n    end\n    info.mesh = Voxel3D.newMesh(data.vertices or {}, data.indices or {})\n    info.texture = loadTexture(info.texPath)\n    info.walkMeshes = {}\n    if not (info.mesh and info.texture) then\n      mod.log:error("%s GPU model creation failed", key)\n      info.failed = true\n      return false\n    end\n    data.vertices, data.indices = nil, nil\n    collectgarbage("step")\n    return true\n  end\n\n  -- Walk frames are loaded lazily. Loading all 19 rigs x 24 poses at startup\n  -- would waste memory on NPC types that are not present on the current map.\n  local function genericWalkMesh(key, frame)\n    local info = MODEL_DEFS[key]\n    if not info or not ensureGeneric(key) then return nil end\n    frame = math.max(1, math.min(info.walkFrames or 1, frame or 1))\n    if info.walkMeshes[frame] then return info.walkMeshes[frame] end\n    local data, err = readMeshData(info.walkPrefix .. string.format("%02d.lua", frame))\n    if not data then\n      mod.log:error("%s walk frame %d load failed: %s", key, frame, tostring(err))\n      return nil\n    end\n    local mesh = Voxel3D.newMesh(data.vertices or {}, data.indices or {})\n    data.vertices, data.indices = nil, nil\n    if mesh then info.walkMeshes[frame] = mesh end\n    collectgarbage("step")\n    return mesh\n  end\n\n  -- `phase == 1` is the same walking flag Dramatic Shape uses to select the\n  -- original Game Boy walk frame. Position supplies a continuous gait phase,\n  -- so the legs alternate across consecutive 16-pixel steps and reflections\n  -- always choose the exact same pose as the visible character.\n  local function genericWalkFrame(px, py, facing, count)\n    local axis = (facing == "left" or facing == "right") and px or py\n    local cycle = (axis / 32) % 1\n    if cycle < 0 then cycle = cycle + 1 end\n    local frame = math.floor(cycle * count) + 1\n    if frame > count then frame = count end\n    return frame\n  end\n'''
if old not in main:
    raise SystemExit('ensureGeneric block not found')
main=main.replace(old,new)

old_draw='''    local key = genericKey(sprite)\n    if key then\n      if not ensureGeneric(key) then\n        return previousDrawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)\n      end\n      local info = MODEL_DEFS[key]\n      local model = worldModel(px, py, y, facing, genericIdle(key), 1)\n      Voxel3D.draw(info.mesh, info.texture, model, 0, NO_SELF_SHADOW)\n      return true\n    end\n'''
new_draw='''    local key = genericKey(sprite)\n    if key then\n      if not ensureGeneric(key) then\n        return previousDrawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)\n      end\n      local info = MODEL_DEFS[key]\n      local mesh = info.mesh\n      local idle = genericIdle(key)\n      if phase == 1 and info.walkFrames and info.walkFrames > 1 then\n        local frame = genericWalkFrame(px, py, facing, info.walkFrames)\n        mesh = genericWalkMesh(key, frame) or mesh\n        -- Walking already contains its own body motion; do not stack the idle\n        -- sway on top of it or the feet look like they skate over the floor.\n        idle = { x=0, y=0, z=0, yaw=0 }\n      end\n      local model = worldModel(px, py, y, facing, idle, 1)\n      Voxel3D.draw(mesh, info.texture, model, 0, NO_SELF_SHADOW)\n      return true\n    end\n'''
if old_draw not in main:
    raise SystemExit('generic draw block not found')
main=main.replace(old_draw,new_draw)
main=main.replace('Gen1 TRUE 3D Characters v1.0.1 unified renderer installed','Gen1 TRUE 3D Characters v1.1.0 rigged walking renderer installed')
main_path.write_text(main,encoding='utf-8')

manifest_path=OUT/'manifest.json'
manifest=json.loads(manifest_path.read_text())
manifest['version']='1.1.0'
manifest['description']='Unified TRUE 3D character pack for Gen1Recomp + Dramatic Shape: Nurse Joy, Professor Oak, and diverse imported NPC models. Generic NPCs now use weight-preserving skeletal walk rigs with animated shoulders, elbows, hips, knees, ankles and feet.'
manifest_path.write_text(json.dumps(manifest,indent=2),encoding='utf-8')

readme='''# Gen1 TRUE 3D Characters v1.1.0\n\nCombined character pack for **Gen1Recomp + Dramatic Shape**.\n\n## New in v1.1.0 — rigged NPC walking\n\nAll 19 generic NPC archetypes from the supplied Miscellaneous NPC pack have been rebuilt from their original weighted SMD skeleton data. Standing poses now use relaxed shoulders/elbows/wrists, and walking uses a shared 12-pose gait with opposite arm/leg swing, hip motion, knee flex, ankle compensation, and proper weighted deformation around the joints.\n\nThe walk animation is activated only while Gen1Recomp reports the NPC in its walking phase. Its animation position is derived from the NPC's actual world position, so consecutive tile steps alternate feet and the visible/reflection draws stay synchronized.\n\n### Special characters\n\n- **Nurse Joy** keeps her existing smooth custom 60-pose idle/arm animation.\n- **Professor Oak** keeps his dedicated natural-hand model and idle.\n- **Player** is still untouched.\n\n### Installation\n\nDisable the older standalone Nurse Joy, Professor Oak, All-NPC, and older combined character mods. Import this ZIP and enable it together with Dramatic Shape.\n\n### Performance\n\nWalk meshes are loaded lazily per model and per pose. The mod does not load hundreds of animation meshes at startup; only NPC types and poses actually encountered are uploaded to the GPU.\n'''
(OUT/'README.md').write_text(readme,encoding='utf-8')

info={
    'version':'1.1.0',
    'base':'Gen1 TRUE 3D Characters v1.0.2',
    'generic_archetypes':19,
    'walk_frames_per_archetype':WALK_FRAMES,
    'rig':'weighted SMD limb hierarchy (shoulder/elbow/wrist + hip/knee/ankle)',
    'notes':'Rebuilt all generic NPC standing meshes and added lazy-loaded skeletal walking frames. Nurse Joy and Oak special renderers preserved.'
}
(OUT/'source'/'BUILD_INFO.json').write_text(json.dumps(info,indent=2),encoding='utf-8')

# Keep build provenance script in source for future revisions.
shutil.copy2('/mnt/data/build_rigged_walks.py',OUT/'source'/'build_rigged_walks.py')

if ZIP.exists(): ZIP.unlink()
with zipfile.ZipFile(ZIP,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for root,dirs,files in os.walk(OUT):
        for fn in files:
            p=Path(root)/fn
            z.write(p,p.relative_to(OUT))
print('ZIP',ZIP,'size',ZIP.stat().st_size)
