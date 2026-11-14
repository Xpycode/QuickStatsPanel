# Gauge ring Wave 1 — rung matrix and arc fit (task 1.1)

Source: integrated run `01_Project/build/GaugePrototypeTests-W1-run02.xcresult` (main after Wave 1 integration, 2026-11-14), suites RingLayoutTests / RingArcLayoutTests. Text measured headless with `RingTypography` fonts at 13/16/12 pt, 6 pt padding. Worst rung of each stat over every slot it can occupy.

Legend: S = label+value+secondary · L = label+value · I = icon+value · O = icon only · X = does not fit.

```
RING-ARC more-arc cannot-fit cases (list fallback): small/2 small/3 small/4 small/5 small/6 small/7 small/8 small/9 small/10 small/11 medium/3 medium/4 medium/5 medium/6 medium/7 medium/8 medium/9 medium/10 medium/11 large/3 large/4 large/5 large/6 large/7 large/8 large/9 large/10 large/11
RING-MATRIX [paired-worst] legend: S=label+value+secondary L=label+value I=icon+value O=icon only X=does not fit
RING-MATRIX [paired-worst] worst rung of each stat over every slot it can occupy; 13/16/12 pt, 6 pt padding
RING-MATRIX [paired-worst] preset n more | CPU   Memor Disk  Netwo Batte GPU   Fans  Power Tempe Load  Uptim
RING-MATRIX [paired-worst] small  1 no  | S     O     O     O     L     L     O     L     I     L     L
RING-MATRIX [paired-worst] small  1 yes | S     O     O     O     L     L     O     L     I     L     L
RING-MATRIX [paired-worst] small  2 no  | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] small  2 yes | S     O     O     O     L     L     O     O     I     L     O
RING-MATRIX [paired-worst] small  3 no  | L     O     O     O     L     L     O     O     O     I     O
RING-MATRIX [paired-worst] small  3 yes | S     O     O     O     L     L     O     O     O     L     O
RING-MATRIX [paired-worst] small  4 no  | S     O     O     O     L     L     O     O     I     L     L
RING-MATRIX [paired-worst] small  4 yes | L     O     O     O     L     L     O     O     O     I     O
RING-MATRIX [paired-worst] small  5 no  | L     O     O     O     L     L     O     O     I     L     O
RING-MATRIX [paired-worst] small  5 yes | L     O     O     O     L     L     O     O     O     I     O
RING-MATRIX [paired-worst] small  6 no  | L     O     O     O     L     L     O     O     O     I     O
RING-MATRIX [paired-worst] small  6 yes | L     O     O     O     L     L     O     O     O     I     O
RING-MATRIX [paired-worst] small  7 no  | O     O     O     O     O     O     O     O     O     O     O
RING-MATRIX [paired-worst] small  7 yes | O     O     O     O     O     O     O     O     O     O     O
RING-MATRIX [paired-worst] small  8 no  | O     O     O     O     O     O     O     O     O     O     O
RING-MATRIX [paired-worst] small  8 yes | O     O     O     O     O     O     O     O     O     O     O
RING-MATRIX [paired-worst] medium 1 no  | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 1 yes | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 2 no  | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 2 yes | S     O     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 3 no  | S     O     L     O     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 3 yes | S     O     L     O     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 4 no  | S     O     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 4 yes | S     O     L     L     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 5 no  | S     O     L     O     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 5 yes | S     O     L     O     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 6 no  | S     O     L     O     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 6 yes | S     O     L     O     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 7 no  | S     O     O     O     L     L     L     L     L     L     L
RING-MATRIX [paired-worst] medium 7 yes | S     O     O     O     L     L     O     L     I     L     L
RING-MATRIX [paired-worst] medium 8 no  | S     O     O     O     L     L     O     L     I     L     L
RING-MATRIX [paired-worst] medium 8 yes | S     O     O     O     L     L     O     O     I     L     O
RING-MATRIX [paired-worst] large  1 no  | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  1 yes | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  2 no  | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  2 yes | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  3 no  | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  3 yes | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  4 no  | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  4 yes | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  5 no  | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  5 yes | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  6 no  | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  6 yes | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  7 no  | S     S     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  7 yes | S     L     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  8 no  | S     L     S     S     S     L     L     L     L     L     L
RING-MATRIX [paired-worst] large  8 yes | S     O     L     L     S     L     L     L     L     L     L
RING-MATRIX [default-modes] legend: S=label+value+secondary L=label+value I=icon+value O=icon only X=does not fit
RING-MATRIX [default-modes] worst rung of each stat over every slot it can occupy; 13/16/12 pt, 6 pt padding
RING-MATRIX [default-modes] preset n more | CPU   Memor Disk  Netwo Batte GPU   Fans  Power Tempe Load  Uptim
RING-MATRIX [default-modes] small  1 no  | L     O     O     O     L     L     O     L     I     L     L
RING-MATRIX [default-modes] small  1 yes | L     O     O     O     L     L     O     L     I     L     L
RING-MATRIX [default-modes] small  2 no  | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] small  2 yes | L     O     O     O     L     L     O     O     I     L     O
RING-MATRIX [default-modes] small  3 no  | L     O     O     O     L     L     O     O     O     I     O
RING-MATRIX [default-modes] small  3 yes | L     O     O     O     L     L     O     O     O     L     O
RING-MATRIX [default-modes] small  4 no  | L     O     O     O     L     L     O     O     I     L     L
RING-MATRIX [default-modes] small  4 yes | L     O     O     O     L     L     O     O     O     I     O
RING-MATRIX [default-modes] small  5 no  | L     O     O     O     L     L     O     O     I     L     O
RING-MATRIX [default-modes] small  5 yes | L     O     O     O     L     L     O     O     O     I     O
RING-MATRIX [default-modes] small  6 no  | L     O     O     O     L     L     O     O     O     I     O
RING-MATRIX [default-modes] small  6 yes | L     O     O     O     L     L     O     O     O     I     O
RING-MATRIX [default-modes] small  7 no  | O     O     O     O     O     O     O     O     O     O     O
RING-MATRIX [default-modes] small  7 yes | O     O     O     O     O     O     O     O     O     O     O
RING-MATRIX [default-modes] small  8 no  | O     O     O     O     O     O     O     O     O     O     O
RING-MATRIX [default-modes] small  8 yes | O     O     O     O     O     O     O     O     O     O     O
RING-MATRIX [default-modes] medium 1 no  | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 1 yes | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 2 no  | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 2 yes | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 3 no  | L     L     L     O     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 3 yes | L     L     L     O     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 4 no  | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 4 yes | L     L     L     L     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 5 no  | L     L     L     O     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 5 yes | L     L     L     O     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 6 no  | L     L     L     O     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 6 yes | L     L     L     O     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 7 no  | L     O     O     O     L     L     L     L     L     L     L
RING-MATRIX [default-modes] medium 7 yes | L     O     O     O     L     L     O     L     I     L     L
RING-MATRIX [default-modes] medium 8 no  | L     O     O     O     L     L     O     L     I     L     L
RING-MATRIX [default-modes] medium 8 yes | L     O     O     O     L     L     O     O     I     L     O
RING-MATRIX [default-modes] large  1 no  | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  1 yes | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  2 no  | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  2 yes | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  3 no  | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  3 yes | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  4 no  | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  4 yes | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  5 no  | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  5 yes | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  6 no  | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  6 yes | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  7 no  | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  7 yes | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  8 no  | L     L     L     S     L     L     L     L     L     L     L
RING-MATRIX [default-modes] large  8 yes | L     L     L     L     L     L     L     L     L     L     L
RING-MATRIX STOP-CONDITION (Medium/8/More below icon+value): paired-worst:memory=O; paired-worst:network=O; paired-worst:fan=O; paired-worst:power=O; paired-worst:disk=O; paired-worst:uptime=O; default-modes:memory=O; default-modes:network=O; default-modes:fan=O; default-modes:power=O; default-modes:disk=O; default-modes:uptime=O
```
