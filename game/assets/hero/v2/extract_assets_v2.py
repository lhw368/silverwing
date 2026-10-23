#!/usr/bin/env python3
"""Reproducible sprite extraction only. Does not redraw or edit the pet originals."""
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np
from scipy import ndimage
import json, hashlib
ROOT=Path(__file__).resolve().parent
PET=Path('/workspace/scratch/03d04e3f78fb/mecha_pet/frames')
SIZE=(512,512); ORIGIN=(256,474)

def parts(path):
    arr=np.array(Image.open(path).convert('RGBA'))
    labels,n=ndimage.label(arr[:,:,3]>90)
    counts=np.bincount(labels.ravel())
    large=np.flatnonzero(counts>1000);large=large[large!=0]
    core=np.isin(labels,large)
    distances,idx=ndimage.distance_transform_edt(~core,return_indices=True)
    owner=labels[idx[0],idx[1]]
    extracted=[]
    for lab in large:
        mask=(owner==lab)&(distances<=22)&(arr[:,:,3]>0)
        cut=arr.copy();cut[~mask,:]=0
        # Transparent RGB is cleared to avoid colored sampling fringes in engines.
        cut[cut[:,:,3]==0,:]=0
        im=Image.fromarray(cut)
        bbox=im.getbbox();extracted.append((bbox,im.crop(bbox)))
    return extracted

def save_pose(state,index,piece,bbox,anchor,scale):
    img=piece.resize((round(piece.width*scale),round(piece.height*scale)),Image.Resampling.LANCZOS)
    x=round(ORIGIN[0]+(bbox[0]-anchor[0])*scale)
    y=round(ORIGIN[1]+(bbox[1]-anchor[1])*scale)
    canvas=Image.new('RGBA',SIZE)
    canvas.alpha_composite(img,(x,y))
    a=np.asarray(canvas)[:,:,3]
    if a.max()==0:raise ValueError('empty sprite')
    # Any >=32 alpha on the canvas border indicates a visible clipped limb/blade.
    assert max(a[0].max(),a[-1].max(),a[:,0].max(),a[:,-1].max())<32,(state,index,'clipped')
    target=ROOT/state/f'{index:02}.png';target.parent.mkdir(exist_ok=True);canvas.save(target)
    return {'file':str(target.relative_to(ROOT)),'source_bbox':list(bbox),'source_anchor':list(anchor),'scale':scale,'visible_bbox':list(canvas.getbbox())}

combat=parts(ROOT.parent/'source/silverwing-combat-sheet.png')
# The core objects are vertically staggered. Explicit centers identify poses robustly.
centers=[(180,220),(550,210),(930,225),(1290,200),(250,580),(570,550),(920,585),(1300,605),(220,950),(575,900),(930,920),(1300,960)]
config=[('idle',0,(200,372)),('attack1',0,(550,372)),('attack1',1,(932,368)),('attack2',0,(1284,382)),('attack3',0,(250,705)),('heavy',0,(565,710)),('heavy',1,(915,711)),('dodge',0,(1294,703)),('dodge',1,(225,1053)),('skill',0,(565,1055)),('hurt',0,(920,1053)),('death',0,(1275,1051))]
states={}
used=set()
for point,(state,index,anchor) in zip(centers,config):
    candidates=[i for i,(box,_) in enumerate(combat) if box[0]<=point[0]<=box[2] and box[1]<=point[1]<=box[3] and i not in used]
    assert len(candidates)==1,(point,candidates)
    i=candidates[0];used.add(i);box,piece=combat[i]
    states.setdefault(state,[]).append(save_pose(state,index,piece,box,anchor,1.024))
assert len(used)==12

run=parts(ROOT/'source/silverwing-run-sheet-v2.png')
centers=[(300,265),(815,270),(1300,270),(300,750),(815,760),(1300,765)]
anchors=[(300,512),(815,512),(1300,512),(300,1014),(815,1014),(1300,1014)]
used=set()
for i,(point,anchor) in enumerate(zip(centers,anchors)):
    matches=[j for j,(box,_) in enumerate(run) if box[0]<=point[0]<=box[2] and box[1]<=point[1]<=box[3] and j not in used]
    assert len(matches)==1,(point,matches)
    j=matches[0];used.add(j);box,piece=run[j]
    states.setdefault('run',[]).append(save_pose('run',i,piece,box,anchor,.62))

jump=parts(ROOT.parent/'source/silverwing-jump-sheet.png')
# Six genuine side-facing poses; no frontal pet jump substitutions.
centers=[(300,320),(795,265),(1310,265),(265,740),(785,765),(1300,830)]
anchors=[(290,504),(790,510),(1310,462),(270,943),(785,986),(1280,986)]
used=set()
for i,(point,anchor) in enumerate(zip(centers,anchors)):
    matches=[j for j,(box,_) in enumerate(jump) if box[0]<=point[0]<=box[2] and box[1]<=point[1]<=box[3] and j not in used]
    assert len(matches)==1,(point,matches)
    j=matches[0];used.add(j);box,piece=jump[j]
    states.setdefault('jump',[]).append(save_pose('jump',i,piece,box,anchor,.672))

# A newly drawn standalone idle replaces the sheet idle at genuine native detail.
# The sheet-derived pose remains reproducible in the previous commit/source data.
native_idle=parts(ROOT/'source/silverwing-idle-native-v2.png')
assert len(native_idle)==1
box,piece=native_idle[0]
states['idle']=[save_pose('idle',0,piece,box,(790,1158),.26)]

rates={'idle':4,'run':9,'jump':12,'attack1':12,'attack2':10,'attack3':10,'heavy':7,'dodge':12,'skill':8,'hurt':10,'death':6}
manifest={'format_version':1,'character':'Silverwing / 银翼','frame_size':[512,512],'origin':[256,474],'facing':'right','standing_visible_height_px':298,'total_unique_art_frames':sum(map(len,states.values())),
'notes':['All frames are actual distinct artwork; the engine may reuse, hold, offset or rotate key poses for timing.','11 combat key poses retained at near-native detail, 1 newly drawn standalone idle, 6 new high-native-detail run poses, and 6 jump key poses generated with the built-in image generation tool.','Six new high-native-detail run keyframes were generated at 462-484px native character height; they are not interpolated pet frames.','The original idle and jump face the viewer and were therefore not reused.','Run and jump use a stowed energy blade; combat poses show the blade.','Sprite origin is ground point at (256,474). Godot Sprite2D offset with centered=true: (0,-218). Preserve original 264px world draw canvas size when comparing v1 and v2.','For physically driven jump, hold jump/02.png while rising, jump/03.png at apex, jump/04.png falling; use 00/01 for takeoff and 05 for landing.','Sprites are normalized key art, not 60 hand-drawn frames per second.'],
'animations':{s:{'fps':rates[s],'loop':s in ['idle','run'],'unique_frames':len(fs),'frames':[f['file'] for f in fs]} for s,fs in states.items()},'extraction':states}
(ROOT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
# Review sheet on a dark game-like background. Labels are QA only, never in sprites.
allframes=[(s,f['file']) for s,fs in states.items() for f in fs]
w=4*256;h=((len(allframes)+3)//4)*282
sheet=Image.new('RGB',(w,h),(15,26,44));d=ImageDraw.Draw(sheet)
for i,(s,f) in enumerate(allframes):
    x=(i%4)*256;y=(i//4)*282
    im=Image.open(ROOT/f).resize((256,256),Image.Resampling.LANCZOS);sheet.paste(im,(x,y),im)
    d.line((x,y+237,x+256,y+237),fill=(30,68,87));d.text((x+12,y+264),f,fill=(190,225,245))
sheet.save(ROOT/'qa/contact-sheet.jpg',quality=94)
print(json.dumps({k:v['unique_frames'] for k,v in manifest['animations'].items()}));print('total',manifest['total_unique_art_frames'])
