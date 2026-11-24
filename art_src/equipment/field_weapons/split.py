"""Rebuild the registered weapons, lighting layers, pickups and icons from their source atlases."""
from argparse import ArgumentParser
from hashlib import sha256
import json
from pathlib import Path
from tempfile import TemporaryDirectory

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter, map_coordinates

SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parents[2]


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def open_atlases(metadata):
    images = {}
    for name, entry in metadata["atlases"].items():
        path = SOURCE / f"{name}.png"
        if sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            raise ValueError(f"Source atlas contents changed: {path}")
        with Image.open(path) as image:
            if image.mode != "RGBA" or image.size != tuple(entry["size"]):
                raise ValueError(f"Unexpected atlas dimensions or channels: {path}")
            images[name] = image.copy()
    return images


def extract(atlas, box):
    rgba = np.asarray(atlas.crop(box), dtype=np.float32)/255.0
    rgba[:,:,3] = np.clip((rgba[:,:,3]-0.29)/0.62,0,1)
    return rgba

def mapped_texture(rgba, target, x_in, x_out, y_in, y_out, box, lights, fixed_bore=None):
    # Oversample the matte and colors in premultiplied form, avoiding a dark or gray edge.
    w,h = target
    scale = 3
    xs = (np.arange(w*scale,dtype=np.float32)+0.5)/scale
    xp = np.interp(xs, x_out, x_in)
    centers_in = np.interp(xs, x_out, y_in)
    centers_out = np.interp(xs, x_out, y_out)
    top,bottom = np.flatnonzero(rgba[:,:,3].max(axis=1)>0.50)[[0,-1]]
    ys = (np.arange(h*scale,dtype=np.float32)[:,None]+0.5)/scale
    yp = np.where(ys<centers_out,
                  top-2.0 + (ys-0.6)*(centers_in-top+2.0)/(centers_out-0.6),
                  centers_in + (ys-centers_out)*(bottom+2.0-centers_in)/(h-0.6-centers_out))
    if fixed_bore is not None:
        source_bore, target_bore, source_grip, target_grip = fixed_bore
        yp = np.broadcast_to(np.interp(ys, [0.6,target_bore,target_grip,h-0.6],
            [top-2.0,source_bore,source_grip,bottom+2.0]), yp.shape)
    xx = np.broadcast_to(xp,yp.shape)
    coords = (yp,xx)
    premul = rgba.copy()
    premul[:,:,:3] *= premul[:,:,3:4]
    pixels = np.stack([map_coordinates(premul[:,:,i], coords, order=1, mode="constant") for i in range(4)],axis=2)
    pixels[:,:,:3] = np.where(pixels[:,:,3:4]>0.003,pixels[:,:,:3]/np.maximum(0.003,pixels[:,:,3:4]),0)
    body = Image.fromarray(np.uint8(np.clip(pixels*255.0+0.5,0,255)), "RGBA").resize(target,Image.Resampling.LANCZOS)
    local_x,local_y = xx+box[0],yp+box[1]
    zone=np.zeros(xx.shape,bool)
    for x0,y0,x1,y1 in lights:
        zone |= (local_x>=x0)&(local_x<x1)&(local_y>=y0)&(local_y<y1)
    rgb = pixels[:,:,:3]
    chroma = rgb.max(axis=2) - rgb.min(axis=2)
    strength = pixels[:,:,3] * np.clip((chroma-0.12)*2.8,0,1) * np.clip((rgb.max(axis=2)-0.35)*2.4,0,1)
    glow = pixels.copy()
    glow[:,:,3] = strength * zone
    glow_img = Image.fromarray(np.uint8(np.clip(glow*255.0+0.5,0,255)), "RGBA").resize(target,Image.Resampling.LANCZOS)
    return body,glow_img

def shape(rgba):
    y,x = np.nonzero(rgba[:,:,3] > 0.5)
    return x.min()-1, x.max()+1, y.min()-1,y.max()+1

def maps_for_firearm(body):
    pixels = np.asarray(body,dtype=np.float32)/255
    alpha = pixels[:,:,3]
    luma = pixels[:,:,:3] @ np.array([.22,.70,.08],dtype=np.float32)
    relief = gaussian_filter(alpha*(0.45 + luma*0.65),1.18)
    dy,dx= np.gradient(relief)
    nx,ny = np.clip(-dx*2.2,-0.5,0.5),np.clip(dy*2.2,-0.5,0.5)
    nz = np.sqrt(1-nx*nx-ny*ny)
    packed = 127.5 * (np.stack((nx,ny,nz),axis=2)+1)
    return Image.fromarray(np.uint8(packed+0.5),"RGB")

def polish_alloy(image):
    pixels = np.asarray(image, dtype=np.float32) / 255.0
    rgb = pixels[:, :, :3]
    luminance = rgb @ np.array([0.23, 0.69, 0.08], dtype=np.float32)
    # Smooth the finest pitting from the base atlas and introduce a cool alloy gradient.
    tone = np.clip(luminance * 0.70 + gaussian_filter(luminance, 0.55) * 0.30, 0, 1)
    cool = np.stack((tone * 1.14 + 0.044, tone * 1.21 + 0.054, tone * 1.31 + 0.079), axis=2)
    saturation = rgb.max(axis=2) - rgb.min(axis=2)
    accent = np.clip((saturation - 0.22) * 1.85, 0, 0.76) * pixels[:, :, 3]
    pixels[:, :, :3] = cool * (1.0 - accent[:, :, None]) + rgb * accent[:, :, None]
    return Image.fromarray(np.uint8(np.clip(pixels * 255 + 0.5, 0, 255)), "RGBA")


def housing_images(images, registration):
    result = {}
    for name, box in registration["housings"].items():
        paint = extract(images["lab_housings"], box)
        image = Image.fromarray(np.uint8(np.clip(paint * 255 + 0.5, 0, 255)), "RGBA")
        result[name] = image.crop(image.getchannel("A").getbbox())
    return result


def apply_inset(body, emission, image, rect):
    x, y, width, height = rect
    inset = image.resize((width, height), Image.Resampling.LANCZOS)
    body.alpha_composite(inset, (x, y))
    pixels = np.asarray(inset, dtype=np.float32) / 255.0
    rgb = pixels[:, :, :3]
    # Keep diagnostic lights separate from reflective ceramic and copper.
    saturation = np.maximum(rgb[:, :, 1], rgb[:, :, 2]) - rgb[:, :, 0]
    pixels[:, :, 3] *= np.clip((saturation - 0.13) * 3.4, 0, 1)
    pixels[:, :, 3] *= np.clip((rgb.max(axis=2) - 0.56) * 3.4, 0, 1)
    layer = Image.fromarray(np.uint8(np.clip(pixels * 255 + 0.5, 0, 255)), "RGBA")
    emission.paste((0, 0, 0, 0), (x, y, x + width, y + height), inset.getchannel("A"))
    emission.alpha_composite(layer, (x, y))


def rebuild(root, out, assets):
    metadata = read_json(SOURCE / "source.json")
    registration = read_json(SOURCE / "registration.json")
    sizes = metadata["output_sizes"]
    images = open_atlases(metadata)
    firearms = registration["firearms"]
    melee = registration["melee"]
    housings = housing_images(images, registration)
    weapons = json.loads((root/'art/weapons/weapons.json').read_bytes())["weapons"]
    for key,(atlas,box,grip,fore,muzzle,lights) in firearms.items():
        rgba = extract(images[atlas],box)
        l,r,t,b=shape(rgba)
        def local(point):
            return point[0] - box[0], point[1] - box[1]
        data = weapons[key]
        w,h = data["size"]
        gx,gy = data["grip"]
        fx,fy = data["foregrip"]
        mx,my = data["muzzle"]
        sgx,sgy = local(grip)
        smx,smy = local(muzzle)
        smx = min(smx,r-2)
        points = [(l,1.0,smy,my),(sgx,gx,sgy,gy),(smx,mx,smy,my),(r,w-0.75,smy,my)]
        if fore:
            sfx,sfy = local(fore)
            points.insert(2,(sfx,fx,sfy,fy))
        a,b,c,d = map(list,zip(*points))
        assert all(i<j for i,j in zip(a,a[1:])) and all(i<j for i,j in zip(b,b[1:])),(key,a,b)
        body,emission = mapped_texture(rgba,(w,h),a,b,c,d,box,lights,(smy,my,sgy,gy))
        body = polish_alloy(body)
        inset, rect = registration["insets"][key]
        apply_inset(body, emission, housings[inset], rect)
        body.save(out/f'{key}.png',optimize=True)
        emission.save(out/f'{key}_glow.png',optimize=True)
        maps_for_firearm(body).save(out/f'{key}_n.png',optimize=True)

    entries=json.loads((root/'data/weapon_art/melee.json').read_bytes())["weapons"]
    for key,(box,grip,lights) in melee.items():
        rgba=extract(images["melee"],box)
        l,r,t,b=shape(rgba)
        entry=entries[key]
        w,h=sizes[entry["texture"].removeprefix("res://")]
        gx,gy=entry["grip"]
        gw=gx*w/entry["size"][0]
        gh=gy*h/entry["size"][1]
        sx,sy=grip[0]-box[0],grip[1]-box[1]
        body,emission = mapped_texture(rgba,(w,h),[l,sx,r],[0.65,gw,w-0.65],[sy]*3,[gh]*3,box,lights)
        body = polish_alloy(body)
        body.save(out/f'{key}.png',optimize=True)
        emission.save(out/f'{key}_glow.png',optimize=True)



    def save(im,relative):
        to=assets/relative
        to.parent.mkdir(parents=True,exist_ok=True)
        im.save(to,optimize=True)

    def fit(im,size,max_dims,rotate=0):
        if rotate:
            im=im.rotate(rotate,Image.Resampling.BICUBIC,expand=True)
        im=im.crop(im.getchannel("A").getbbox() or im.getbbox() or (0,0,*im.size))
        im=im.copy()
        ratio=min(max_dims[0]/im.width,max_dims[1]/im.height)
        im=im.resize((round(im.width*ratio),max(1,round(im.height*ratio))),Image.Resampling.LANCZOS)
        result=Image.new("RGBA",size)
        result.alpha_composite(im,((size[0]-im.width)//2,(size[1]-im.height)//2))
        return result

    profiles={"melee_dagger":"mono_dagger","melee_blade":"thermal_blade","melee_glaive":"ion_glaive",
              "melee_maul":"hydraulic_maul","melee_whip":"mono_whip"}
    for key in [*firearms,*melee]:
        is_melee=key in melee
        prefix="art/weapons/melee" if is_melee else "art/weapons"
        body=Image.open(out/f"{key}.png")
        emit=Image.open(out/f"{key}_glow.png")
        for trailing in ("", "_glow") if is_melee else ("","_glow","_n"):
            save(Image.open(out/f"{key}{trailing}.png"),f"{prefix}/{key}{trailing}.png")
        # Reuse the real silhouette for installed pickup and inventory icon families.
        combined=Image.alpha_composite(body,emit)
        world_base=Path(f"art/items/world/{key}.png")
        if world_base.as_posix() in sizes:
            canvas=sizes[world_base.as_posix()]
            if key=="melee_whip":
                # The loose cable is part of the dropped item, while the held handle uses the cable rig.
                coil=Image.new("RGBA",(104,62))
                brush=ImageDraw.Draw(coil)
                brush.ellipse((10,8,88,54),outline=(31,23,28,255),width=5)
                brush.ellipse((10,8,88,54),outline=(179,139,147,255),width=2)
                brush.ellipse((17,13,82,50),outline=(86,64,78,255),width=2)
                handle=body.resize((75,12),Image.Resampling.BICUBIC).rotate(18,Image.Resampling.BICUBIC,expand=True)
                coil.alpha_composite(handle,(16,26))
                save(fit(coil,canvas,(84,74)),world_base)
                save(Image.new("RGBA",canvas),world_base.with_stem(key+"_glow"))
            else:
                angle=22 if is_melee else 18
                # The same fitted extent aligns the emissive insert with the pickup sprite.
                rt=body.rotate(angle,Image.Resampling.BICUBIC,expand=True)
                ge=emit.rotate(angle,Image.Resampling.BICUBIC,expand=True)
                bounds=rt.getchannel("A").getbbox()
                rt,ge=rt.crop(bounds),ge.crop(bounds)
                scale=min((canvas[0]-12)/rt.width,(canvas[1]-12)/rt.height)
                size=round(rt.width*scale),max(1,round(rt.height*scale))
                shift=((canvas[0]-size[0])//2,(canvas[1]-size[1])//2)
                for sprite,tail in [(rt,""),(ge,"_glow")]:
                    layer=Image.new("RGBA",canvas)
                    layer.alpha_composite(sprite.resize(size,Image.Resampling.LANCZOS),shift)
                    save(layer,world_base.with_stem(key+tail))
        common=Path(f"art/items/weapons/{key}.png")
        card=profiles.get(key,key)
        for path in (common,Path(f"art/items/icons/{card}.png"),Path(f"art/items/icons/{card}_hd.png")):
            if path.as_posix() in sizes:
                dimensions=sizes[path.as_posix()]
                art=combined if key!="melee_whip" or world_base.as_posix() not in sizes else Image.open(assets/world_base)
                w,h=dimensions
                save(fit(art,dimensions,(w-max(4,w//9),h-max(4,h//9)),0 if path==common or key=="melee_whip" else 14),path)

    baton_atlas = images["batons"]
    for key, box in registration["batons"].items():
        path=Path(f"art/weapons/{key}.png")
        rgba=extract(baton_atlas,box)
        left,right,top,bottom=shape(rgba)
        w,h=sizes[path.as_posix()]
        pivot=(top+bottom)*.5
        body,_=mapped_texture(rgba,(w,h),[left,right],[0.75,w-1],[pivot,pivot],[h*.5,h*.5],box,[])
        save(body,path)



if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--out", type=Path, default=ROOT)
    args = parser.parse_args()
    with TemporaryDirectory(prefix="nestegg-field-weapons-") as work:
        rebuild(args.project, Path(work), args.out)
