# RAM in 60 Sekunden – self-contained animated vertical explainer, no external visual assets.
import os, math, asyncio, subprocess, pathlib, random, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import edge_tts

W,H,FPS,SEC=720,1280,25,60
D=pathlib.Path(".")
OUT=D/"RAM_60S_NEURAL_FULLHD.mp4"
A=(70,239,209); BLUE=(110,167,255); GOLD=(255,201,112); RED=(255,111,132)
WHITE=(241,247,255); GREY=(149,169,194); DARK=(8,16,30)
cuts=[0,7.5,15,22.5,30,37.5,45,52.5,60]
speech=[
"Was macht RAM eigentlich? Ohne Arbeitsspeicher wäre dein Computer bei fast jeder Aufgabe viel langsamer.",
"RAM hält Daten geöffneter Programme griffbereit, damit der Prozessor schnell darauf zugreifen kann.",
"Deine SSD speichert dauerhaft. Beim Öffnen eines Programms wandern benötigte Daten in den RAM.",
"RAM besteht aus winzigen Speicherzellen. Sie halten elektrische Zustände und werden regelmäßig aufgefrischt.",
"Je mehr Programme gleichzeitig laufen, desto mehr Arbeitsspeicher wird belegt. Spiele brauchen oft besonders viel.",
"Wenn RAM voll wird, lagert das System Daten aus. Der langsamere Speicher kann Ruckler verursachen.",
"Acht Gigabyte: einfache Aufgaben. Sechzehn: guter Standard. Zweiunddreißig: anspruchsvolle Projekte und Multitasking.",
"Merke dir: SSD speichert, RAM hält bereit, die CPU rechnet. Mehr RAM allein erhöht nicht automatisch die FPS."
]
subtitles=[
("DAS BRAUCHT DEIN PC","FÜR GESCHWINDIGKEIT."),
("AKTIVE DATEN","SOFORT GRIFFBEREIT."),
("SSD → RAM → CPU","DER DATENWEG."),
("MILLIARDEN","SPEICHERZELLEN."),
("MEHR PROGRAMME","MEHR AUSLASTUNG."),
("WENN RAM","VOLL WIRD ..."),
("WIE VIEL RAM","BRAUCHST DU?"),
("SSD SPEICHERT.","RAM HÄLT BEREIT.")
]
FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
def font(n,b=True):return ImageFont.truetype(BOLD if b else FONT,n)
def mix(c,d,k):return tuple(int(c[i]*(1-k)+d[i]*k) for i in range(3))
def clamp(x):return max(0,min(1,x))
def ease(x):x=clamp(x);return x*x*(3-2*x)
def text(draw,xy,s,size=40,color=WHITE,anchor=None,bold=True):
 f=font(size,bold);draw.text(xy,s,font=f,fill=color,anchor=anchor,stroke_width=0)
def centered(draw,y,s,size=40,color=WHITE):
 f=font(size,True)
 while draw.textbbox((0,0),s,font=f)[2]>635 and size>22:
  size-=1;f=font(size,True)
 draw.text((W/2,y),s,font=f,fill=color,anchor="mt")
def rr(draw,box,fill,r=18,outline=None,width=2):
 draw.rounded_rectangle(tuple(int(q) for q in box),radius=r,fill=fill,outline=outline,width=width)
def circle(draw,x,y,r,fill):
 draw.ellipse((int(x-r),int(y-r),int(x+r),int(y+r)),fill=fill)
def glow(im,x,y,r,color,alpha=60):
 layer=Image.new("RGBA",(W,H));d=ImageDraw.Draw(layer)
 circle(d,x,y,r,(*color,alpha))
 im.alpha_composite(layer.filter(ImageFilter.GaussianBlur(r*.48)))
# background rendered once
Y,X=np.mgrid[0:H,0:W]
base=np.zeros((H,W,3),np.float32)
base[:,:,0]=7+4*Y/H
base[:,:,1]=13+8*Y/H
base[:,:,2]=27+9*Y/H
halo=np.exp(-((X-515)**2/(440**2)+(Y-710)**2/(650**2))*1.45)
for c,col in enumerate(A):base[:,:,c]+=halo*col*.07
BG=Image.fromarray(base.clip(0,255).astype("uint8"),"RGB").convert("RGBA")
rng=random.Random(13)
stars=[(rng.randrange(45,680),rng.randrange(180,1120),rng.choice((1,1,1,2))) for _ in range(77)]
def draw_bg(t,scene):
 im=BG.copy();d=ImageDraw.Draw(im,"RGBA")
 for i,(x,y,r) in enumerate(stars):
  xx=x+9*math.sin(t*.19+i)
  yy=(y+t*(1+i%3)*1.6)%1040+110
  circle(d,xx,yy,r,(90,190,200,36+int(23*math.sin(t+i)**2)))
 for y in range(280,1110,96):
  d.line((35,y,690,y),fill=(66,114,145,17),width=1)
 d.line((39,139,681,139),fill=(125,175,205,90),width=2)
 rr(d,(42,62,77,97),A,10)
 text(d,(53,67),"R",22,DARK)
 text(d,(92,66),"INSIDE TECH",22,WHITE)
 text(d,(680,72),f"{60-min(59,int(t)):02d}s",22,GREY,anchor="ra")
 for i in range(8):
  x=40+i*82
  rr(d,(x,123,x+71,128),(31,52,69),2)
  a=1 if i<scene else ease((t-cuts[i])/7.5) if i==scene else 0
  if a>0:rr(d,(x,123,x+max(3,71*a),128),A,2)
 d.line((40,1165,680,1165),fill=(83,133,163,90),width=2)
 text(d,(43,1194),"RAM ERKLÄRT  /  60 SEKUNDEN",18,GREY)
 text(d,(680,1194),f"{int(t):02d} / 60",18,GREY,anchor="ra")
 return im
def board(im,t,x=360,y=755,scale=1,spin=True):
 # An optically layered 3D-looking PCB with metallic contacts and raised DRAM packages.
 sw,sh=int(570*scale),int(244*scale)
 if sw<5 or sh<5:return
 lay=Image.new("RGBA",(570,250),(0,0,0,0));d=ImageDraw.Draw(lay,"RGBA")
 d.polygon([(22,42),(551,42),(551,206),(22,206)],fill=(12,55,62,255))
 d.polygon([(22,42),(551,42),(542,54),(33,54)],fill=(52,149,158,255))
 d.polygon([(551,42),(565,56),(565,220),(551,206)],fill=(5,35,41,255))
 rr(d,(22,42,551,208),(12,66,69,255),13,(98,199,193,210),3)
 for p in range(36):
  xx=33+p*14.4
  d.rectangle((xx,205,xx+9,232),fill=(229,172+int(p%3)*13,78,255))
 for q in range(9):
  cx=40+q*56
  rr(d,(cx,64,cx+47,182),(11,21,35,255),7,(45,103,110,255),2)
  rr(d,(cx+4,69,cx+42,177),(26,41,60,255),5)
  for k in range(4):
   d.line([(cx+8,81+21*k),(cx+33,81+21*k)],fill=(61,123,139,115),width=1)
 for j in range(42):
  px=26+j*12.5
  d.line([(px,194),(px+18,190-j%7)],fill=(82,220,171,65),width=1)
 rr(d,(186,189,360,204),(14,39,43,255),5)
 text(d,(271,195),"DDR5  /  RAM",13,A,anchor="mm")
 # Moving teal edge highlight
 highlight=int((t*.65%1)*540)+20
 d.line((highlight,48,highlight+20,48),fill=(160,255,233,255),width=4)
 angle=-8+4*math.sin(t*.32) if spin else -9
 lay=lay.resize((sw,sh),Image.Resampling.LANCZOS).rotate(angle,expand=True,resample=Image.Resampling.BICUBIC)
 x0=int(x-lay.width/2);y0=int(y-lay.height/2)
 shadow=Image.new("RGBA",(W,H));sd=ImageDraw.Draw(shadow)
 sd.ellipse((x-sw*.49,y+sh*.14,x+sw*.52,y+sh*.88),fill=(0,0,0,180))
 im.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(29)))
 im.alpha_composite(lay,(x0,y0))
def head(im,eyebrow,one,two,desc="",accent=A):
 d=ImageDraw.Draw(im)
 rr(d,(42,200,42+min(635,28+len(eyebrow)*15),245),(15,43,51),14,(46,116,115),1)
 text(d,(58,211),eyebrow,17,accent)
 centered(d,294,one,68,WHITE)
 centered(d,380,two,68,accent)
 if desc:centered(d,489,desc,24,GREY)
def caption(im,scene):
 d=ImageDraw.Draw(im)
 rr(d,(38,1029,682,1133),(12,26,42),24,(58,104,124),2)
 d.rectangle((57,1052,63,1110),fill=A)
 for k,s in enumerate(subtitles[scene]):
  size=33
  f=font(size)
  while d.textbbox((0,0),s,font=f)[2]>585 and size>20:size-=1;f=font(size)
  text(d,(82,1041+k*48),s,size,WHITE if k==0 else A)
def card(d,x,y,w,h,title,txt,accent=A):
 rr(d,(x,y,x+w,y+h),(13,32,49),20,(55,111,122),2)
 rr(d,(x+14,y+15,x+22,y+h-15),accent,4)
 text(d,(x+38,y+16),title,24,WHITE)
 text(d,(x+38,y+54),txt,17,GREY, bold=False)
def flow(d,x1,y1,x2,y2,t,accent=A):
 d.line((x1,y1,x2,y2),fill=mix((35,65,85),accent,.4),width=5)
 for n in range(8):
  p=((t*.41+n/8)%1)
  xx=x1+(x2-x1)*p; yy=y1+(y2-y1)*p
  circle(d,xx,yy,5,accent)
def render(t):
 scene=min(7,int(t/7.5));st=t-7.5*scene
 im=draw_bg(t,scene);d=ImageDraw.Draw(im)
 enter=ease(st/.8)
 if scene==0:
  head(im,"01  /  INTRO","WAS MACHT","RAM?", "DEIN ARBEITSSPEICHER")
  glow(im,365,760,180,A,40)
  board(im,t,360,780,1.03)
  rr(d,(229,938,491,988),(17,57,64),16,(65,153,146),2)
  text(d,(360,952),"SCHNELL. TEMPORÄR.",20,A,anchor="mt")
 elif scene==1:
  head(im,"02  /  GRUNDFUNKTION","DATEN SOFORT","GRIFFBEREIT.","Der schnelle Arbeitsplatz der CPU")
  rr(d,(74,595,646,960),(10,34,48),29,(48,114,118),3)
  text(d,(103,622),"AKTIVER SPEICHER",22,A)
  filled=int(ease(st/6)*40)
  for q in range(40):
   x=108+(q%8)*66;y=702+(q//8)*46
   rr(d,(x,y,x+49,y+30),A if q<filled else (27,72,78),6)
  text(d,(100,911),f"{min(100,round(filled/40*100)):02d}%  BELEGT",21,WHITE)
 elif scene==2:
  head(im,"03  /  DATENFLUSS","SSD → RAM","→ CPU","Daten reisen zum Prozessor",BLUE)
  card(d,62,615,176,136,"SSD","DATEIEN",BLUE)
  card(d,277,615,166,136,"RAM","AKTIV",A)
  card(d,481,615,180,136,"CPU","RECHNET",GOLD)
  flow(d,240,681,274,681,st,A);flow(d,445,681,478,681,st,GOLD)
  board(im,t,360,923,.65)
 elif scene==3:
  head(im,"04  /  HARDWARE","MILLIARDEN","KLEINE ZELLEN","Elektrische Zustände im DRAM",BLUE)
  rr(d,(83,601,637,955),(10,30,47),29,(57,88,131),3)
  for i in range(10):
   for j in range(7):
    x=103+i*52;y=632+j*43
    on=(i*7+j+int(st*4))%9<6
    rr(d,(x,y,x+39,y+29),A if on else (31,64,90),6)
  text(d,(360,982),"DRAM  /  STÄNDIGES AUFFRISCHEN",18,GREY,anchor="mt")
 elif scene==4:
  head(im,"05  /  MULTITASKING","MEHR APPS","MEHR RAM.","Mehr gleichzeitig = mehr belegt")
  for i,n in enumerate(("BROWSER","SPIEL","DISCORD","EDITOR")):
   x=70+(i%2)*296;y=622+(i//2)*118
   rr(d,(x,y,x+278,y+100),(13,31,49),20,(64,108,129),2)
   rr(d,(x+20,y+22,x+63,y+65),[BLUE,GOLD,A,RED][i],12)
   text(d,(x+78,y+33),n,18,WHITE)
  amount=17+int(ease(st/7)*76)
  rr(d,(70,888,649,950),(12,33,47),25,(53,115,112),2)
  rr(d,(87,905,87+max(12,int(amount/100*544)),934),A if amount<82 else RED,11)
  text(d,(360,963),f"{amount}% RAM-AUSLASTUNG",23,A,anchor="mt")
 elif scene==5:
  head(im,"06  /  LIMIT","WENN RAM","VOLL WIRD ...","Kann der PC ausbremsen",RED)
  rr(d,(81,603,642,791),(13,31,48),24,(77,108,124),2)
  text(d,(360,625),"RAM",33,WHITE,anchor="mt")
  rr(d,(114,700,612,737),(55,31,48),11,(157,71,94),2)
  rr(d,(122,707,607,730),RED,7)
  text(d,(360,812),"100% BELEGT",30,RED,anchor="mt")
  for i in range(8):
   p=(st*.25+i/8)%1
   x=195+328*p
   circle(d,x,903,7,BLUE)
  text(d,(360,953),"AUSLAGERN → SSD",23,BLUE,anchor="mt")
 elif scene==6:
  head(im,"07  /  KAUFBERATUNG","8, 16 ODER","32 GB?","Kommt auf deine Aufgaben an",GOLD)
  for i,(num,txt) in enumerate((("8 GB","EINFACHE NUTZUNG"),("16 GB","GUTER ALLROUNDER"),("32 GB","GROSSE PROJEKTE"))):
   y=587+i*131
   rr(d,(78,y,641,y+108),(17,50,61) if i==1 else (12,29,47),22,A if i==1 else (47,80,104),3)
   text(d,(104,y+18),num,41,A if i==1 else WHITE)
   text(d,(329,y+38),txt,17,GREY)
 elif scene==7:
  head(im,"08  /  FAZIT","RAM IST","TEAMWORK.","Schnell ist nur das Zusammenspiel")
  board(im,t,360,718,.84)
  rr(d,(62,896,657,981),(12,36,47),22,(55,116,114),2)
  centered(d,910,"SSD SPEICHERT • CPU RECHNET",22,WHITE)
  centered(d,947,"MEHR RAM ≠ AUTOMATISCH MEHR FPS",15,A)
 caption(im,scene)
 return im.convert("RGB")

async def voice():
 parts=[]
 for i,line in enumerate(speech):
  dest=D/f"voice_{i}.mp3"
  for attempt in range(4):
   try:
    c=edge_tts.Communicate(line,"de-DE-ConradNeural",rate="+7%",pitch="+0Hz")
    await c.save(str(dest))
    if dest.stat().st_size<1000:raise RuntimeError("short audio file")
    break
   except Exception as e:
    print("TTS retry",i,attempt,str(e),flush=True)
    if attempt==3:raise
    await asyncio.sleep((attempt+1)*2)
  parts.append(dest)
 return parts
def probe(f):
 return float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","default=nw=1:nk=1",str(f)]).decode().strip())
def create_voice(parts):
 padded=[]
 for i,p in enumerate(parts):
  dur=probe(p)
  target=7.12
  speed=max(1.0,dur/target)
  out=D/f"fit_{i}.wav"
  af=f"atempo={speed:.5f},aresample=48000,apad,atrim=duration={target:.3f},volume=2.2"
  subprocess.run(["ffmpeg","-y","-loglevel","error","-i",str(p),"-af",af,"-ac","1","-ar","48000",str(out)],check=True)
  padded.append(out)
 args=["ffmpeg","-y","-loglevel","error"]
 for p in padded:args+=["-i",str(p)]
 blocks=[]
 for i in range(8):
  delay=int((cuts[i]+.24)*1000)
  blocks.append(f"[{i}:a]adelay={delay}:all=1[v{i}]")
 blocks.append("".join(f"[v{i}]" for i in range(8))+"amix=inputs=8:normalize=0,alimiter=limit=0.85,atrim=duration=60[out]")
 args+=["-filter_complex",";".join(blocks),"-map","[out]","-ar","48000","-ac","2","voice.wav"]
 subprocess.run(args,check=True)
def music():
 sr=32000;n=60*sr
 z=np.arange(n,dtype=np.float64)/sr
 # Soft ambient synth, warm sustained chord, with rhythmic particles and a restrained beat
 vv=np.zeros(n,dtype=np.float32)
 for fq,amp in ((110,.008),(164.81,.007),(220,.004),(329.63,.004)):
  vv+=amp*np.sin(2*np.pi*fq*z+0.12*np.sin(2*np.pi*.15*z)).astype(np.float32)
 beat=(z%1.875)
 vv+=.014*np.sin(2*np.pi*(55+52*np.exp(-beat*28))*beat)*np.exp(-beat*17)
 zz=np.clip(vv,-.12,.12)
 with wave.open("music.wav","wb") as f:
  f.setnchannels(1);f.setsampwidth(2);f.setframerate(sr);f.writeframes((zz*32767).astype("<i2").tobytes())
def video():
 enc=subprocess.Popen(["ffmpeg","-y","-loglevel","error","-f","rawvideo","-pixel_format","rgb24","-video_size",f"{W}x{H}","-framerate",str(FPS),"-i","pipe:0","-vf","scale=1080:1920:flags=lanczos,format=yuv420p","-c:v","libx264","-preset","veryfast","-crf","21","-movflags","+faststart","-t","60","visual.mp4"],stdin=subprocess.PIPE)
 try:
  for frame in range(60*FPS):
   img=render(frame/FPS)
   enc.stdin.write(img.tobytes())
   if frame%250==0:print("Rendered",frame,flush=True)
 finally:
  enc.stdin.close()
  r=enc.wait()
  if r!=0:raise RuntimeError(f"video render {r}")
def mux():
 subprocess.run(["ffmpeg","-y","-loglevel","error","-i","visual.mp4","-i","voice.wav","-i","music.wav","-filter_complex","[1:a]volume=1.0[spoken];[2:a]volume=0.47[bg];[spoken][bg]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[a]","-map","0:v","-map","[a]","-c:v","copy","-c:a","aac","-b:a","192k","-ar","48000","-t","60","-movflags","+faststart",str(OUT)],check=True)
 print("OUTPUT",OUT,OUT.stat().st_size,probe(OUT),flush=True)
if __name__=="__main__":
 if os.environ.get("PREVIEW"):
  render(float(os.environ["PREVIEW"])).save("preview.jpg");print("preview generated")
 else:
  parts=asyncio.run(voice())
  create_voice(parts)
  music()
  video()
  mux()
