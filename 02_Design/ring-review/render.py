"""Deterministic design mockups, not running app screenshots. SVG units model points."""
from pathlib import Path
from html import escape
import math
P=Path(__file__).parent
parts=[]
def text(x,y,s,size=14,color='#e9edef'):
    parts.append(f'<text x="{x}" y="{y}" font-family="Arial" font-size="{size}" fill="{color}">{escape(s)}</text>')
def rect(x,y,w,h,fill='#24292d',stroke='#475159',r=6):
    parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}"/>')
def line(points,color='#84b5dc',width=2,dash=''):
    parts.append(f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="{width}" stroke-dasharray="{dash or 'none'}"/>')
data=[('CPU','24%','52°C'),('Memory','18.4 GB','of 32 GB'),('Network','999.9 MB/s','Up 128.4 MB/s'),('Battery','82%','4:12 remaining'),('Power','28 W','Input 65 W'),('Disk','Read 148 MB/s','Write 12 MB/s'),('GPU','12%','54°C'),('Fans','Unavailable','No current reading')]
def wedge(cx,cy,inner,outer,angle,span,selected=False):
    a,b=angle-span/2+0.004,angle+span/2-0.004
    def point(r,t): return f'{cx+r*math.cos(t):.2f},{cy+r*math.sin(t):.2f}'
    large=int(b-a>math.pi)
    path=f'M {point(outer,a)} A {outer},{outer} 0 {large} 1 {point(outer,b)} L {point(inner,b)} A {inner},{inner} 0 {large} 0 {point(inner,a)} Z'
    parts.append(f'<path d="{path}" fill="{"#30473f" if selected else "#24292d"}" stroke="{"#a7c9e2" if selected else "#475159"}"/>')
def label(cx,cy,s):
    # Horizontal text is centred inside the sector, with no rectangular tile.
    for dy,value,size,color in [(-16,s[0],13,'#bac4cb'),(7,s[1],16,'#e9edef'),(26,s[2],12,'#bac4cb')]:
        parts.append(f'<text x="{cx}" y="{cy+dy}" text-anchor="middle" font-family="Arial" font-size="{size}" fill="{color}">{escape(value)}</text>')
def ring(cx,cy,n=8,selected=None,more=True):
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="260" fill="#1c2125" stroke="#394249"/>')
    for i,s in enumerate(data[:n]):
        a=-math.pi/2+i*2*math.pi/n
        wedge(cx,cy,100,260,a,2*math.pi/n if n>1 else math.pi/3,s[0]==selected)
        label(round(cx+185*math.cos(a)),round(cy+185*math.sin(a)),s)
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="92" fill="#1c2125" stroke="#475159"/>')
    text(cx-49,cy-32,'QuickStatsPanel',12,'#bac4cb')
    text(cx-34,cy-10,'Drag centre',12,'#bac4cb')
    if more:
        line(f'{cx-70},{cy+3} {cx+70},{cy+3}', '#475159',1)
        text(cx-28,cy+27,'More · 4',14,'#a7c9e2')
    line(f'{cx-65},{cy+39} {cx+65},{cy+39}', '#475159',1)
    text(cx-24,cy+62,'Settings',12)
def detail(x,y,title='CPU',held=False):
    rect(x,y,300,295)
    text(x+16,y+26,title+' details',18);text(x+16,y+49,'Held open' if held else 'Preview · click stat to hold',12,'#bac4cb')
    text(x+276,y+25,'×',18)
    text(x+16,y+88,'24% usage' if title=='CPU' else 'Load · 1 minute: 2.41',22)
    text(x+16,y+113,'Temperature 52°C' if title=='CPU' else '5 minutes: 2.12 · 15 minutes: 1.86',13,'#bac4cb')
    line(f'{x+16},{y+200} {x+285},{y+200}', '#475159',1)
    line(' '.join(f'{x+16+i*22},{y+185-v}' for i,v in enumerate([4,10,6,25,18,40,12,32,23,15,30,20,25])), '#8dc3b1')
    text(x+16,y+225,'Illustrative history',12,'#bac4cb')
    text(x+16,y+265,'Existing configured rows continue here',12,'#bac4cb')
def start(title,sub,w=1400,h=720):
    parts.clear();parts.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">');rect(0,0,w,h,'#12171b','#12171b',0);text(34,42,title,26);text(34,70,sub,14,'#bac4cb')
def save(name):
    parts.append('</svg>');(P/(name+'.svg')).write_text('\n'.join(parts))
start('01 / Favourites → detail','Design proposal · illustrative readings · dotted blue route is an annotation, not UI')
ring(350,355,selected='CPU');detail(730,217)
line('350,170 445,170 630,170 730,247',dash='6 5');text(620,185,'Protected travel route',13,'#a7c9e2')
text(50,650,'350 ms dwell previews. Click holds. Hover cannot replace a held detail.',17)
text(50,680,'The centre stays quiet; More and Settings have separate targets. No duplicate selected reading.',15,'#bac4cb');save('01-favourite-detail')
start('02 / More → additional stat → detail','One additional ring only · favourites stay fixed · this full arrangement requires a generous workspace',1500,1000)
ring(490,515)
outer=[('Load','2.41','1-minute average'),('Uptime','3d 04h','Since startup'),('Temperatures','Nominal','CPU 52°C'),('Top process','WindowServer','8.2% CPU')]
for i,s in enumerate(outer):
    a=-math.pi/2+i*math.pi/2
    wedge(490,515,274,410,a,math.pi/2,s[0]=='Load')
    label(round(490+342*math.cos(a)),round(515+342*math.sin(a)),s)
detail(1120,230,'Load',True)
line('550,537 590,430 600,225 560,173 1000,173 1120,255',dash='6 5')
text(1045,610,'More stays open while its',14,'#bac4cb');text(1045,633,'detail is in use.',14,'#bac4cb')
text(35,975,'Escape: close detail → close More → hide HUD. A click on More closes its entire branch.',17);save('02-more-detail')
start('03 / Screen-edge fallback','1024 × 640 point workspace proposal · list replaces outer ring · card stays readable',1100,760)
rect(38,95,1024,640,'#192025','#65737d',0)
ring(350,375,selected=None)
rect(670,185,380,480,'#20262b')
text(686,212,'More · 4',16)
for i,s in enumerate(outer):
    rect(686+(i%2)*178,227+(i//2)*45,168,36,'#344350' if i==0 else '#24292d')
    text(696+(i%2)*178,250+(i//2)*45,s[0],12)
detail(707,335,'Load',True)
line('410,397 620,397 670,250 686,245',dash='6 5')
text(62,690,'The More list and detail share a fixed side area; list rows remain available.',14,'#bac4cb')
text(62,715,'Choose the side and reserve space on summon. Never move the hovered target.',14,'#bac4cb');save('03-edge-fallback')
start('04 / Sparse favourites','Left: one enabled stat. Right: ten enabled, six favourites. Positions freeze for the current summon.',1400,700)
ring(340,350,n=1,more=False);ring(1030,350,n=6)
text(70,625,'1 favourite: keep the hub; no automatic promotion.',16)
text(730,625,'6 favourites: distribute at summon, then freeze.',16)
text(70,650,'Unavailable favourites keep their slot. Explicit membership/order edits apply on the next summon.',15,'#bac4cb');save('04-sparse-fixtures')
