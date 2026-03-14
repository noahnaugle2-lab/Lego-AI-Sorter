// ============================================================
// LEGO AI Sorting Machine v4 Hybrid — Engineering Drawing
// Third-angle orthographic projection
// Main view: front elevation cross-section (1:4 scale)
// Inset: plan view (1:4 scale)
// Sheet: 560 × 370 mm
//
// Render:
//   openscad --preview --projection=ortho \
//     --camera=280,185,900,280,185,0 \
//     --imgsize=2240,1480 \
//     -o technical_drawing.png technical_drawing.scad
// ============================================================

$fn = 32;

// ── SCALE & OFFSETS ────────────────────────────────────────
S  = 0.25;  // 1:4 scale — machine mm × S = sheet mm

// Main front elevation origin (bottom-left corner of view)
MX = 25;    // sheet x of machine x=0
MZ = 52;    // sheet y of machine z=0

// Plan view origin
PX = 25;    // sheet x of machine x=0
PY = 10;    // sheet y of machine y=0

// Helper: machine coords → sheet coords (front elevation)
function mx(x) = MX + x * S;
function mz(z) = MZ + z * S;

// Helper: machine coords → sheet coords (plan view)
function px(x) = PX + x * S;
function py(y) = PY + y * S;

// ── DRAWING HEIGHT LAYERS ──────────────────────────────────
Z_FILL = 0;       // background fills
Z_HATCH= 0.05;    // hatch on top of fill
Z_LINE = 0.1;     // outlines on top
Z_CL   = 0.15;    // centerlines on top of outlines
Z_DIM  = 0.20;    // dimensions above everything
Z_TXT  = 0.25;    // text topmost

DH = 0.2;   // extrusion depth

// ── COLOURS ────────────────────────────────────────────────
C_PAPER = [1.00, 1.00, 1.00];
C_COMP  = [0.88, 0.91, 0.95];   // component body
C_FRAME = [0.78, 0.80, 0.82];   // aluminium extrusion
C_BELT  = [0.25, 0.25, 0.25];   // dark belt/rubber
C_CAM   = [0.15, 0.15, 0.15];   // black camera
C_CAR   = [0.60, 0.68, 0.90];   // carousel
C_PLAT  = [0.92, 0.92, 0.72];   // platform trays
C_STACK = [0.92, 0.72, 0.28];   // pancake stack
C_GATE  = [0.28, 0.72, 0.42];   // gate tree
C_ELEC  = [0.30, 0.50, 0.88];   // electronics box
C_STEP  = [0.70, 0.58, 0.45];   // step feeder
C_LINE  = [0.10, 0.10, 0.10];   // dark outlines
C_DIM   = [0.10, 0.20, 0.72];   // blue dimensions
C_CL    = [0.85, 0.08, 0.08];   // red centerlines
C_HATCH = [0.50, 0.50, 0.50];   // section hatch
C_BORD  = [0.00, 0.00, 0.00];   // black borders
C_TXT   = [0.00, 0.00, 0.00];
C_TTXT  = [0.12, 0.18, 0.42];   // title text dark blue

// ── 2D DRAW HELPER ─────────────────────────────────────────
module draw(c, z=Z_FILL) {
    color(c) translate([0, 0, z]) linear_extrude(DH) children();
}

// Filled+outlined rectangle
module frect(x, y, w, h, fc, lw=0.35, z_fill=Z_FILL) {
    translate([x, y]) {
        draw(fc, z_fill) square([w, h]);
        draw(C_LINE, Z_LINE) difference() {
            square([w, h]);
            translate([lw, lw]) square([max(0,w-2*lw), max(0,h-2*lw)]);
        }
    }
}

// Filled+outlined circle
module fcirc(cx, cy, r, fc, lw=0.30) {
    translate([cx, cy]) {
        draw(fc, Z_FILL)   circle(r=r);
        draw(C_LINE, Z_LINE) difference() {
            circle(r=r);
            circle(r=max(0, r-lw));
        }
    }
}

// Straight line segment
module seg(x1, y1, x2, y2, w=0.35, c=C_LINE, z=Z_LINE) {
    dx = x2-x1; dy = y2-y1;
    L = sqrt(dx*dx + dy*dy);
    if (L > 0.01) {
        a = atan2(dy, dx);
        draw(c, z)
        translate([x1, y1]) rotate([0,0,a])
            square([L, w]);
    }
}

// Dashed line (centerline)
module dline(x1, y1, x2, y2, dash=2.5, gap=1.5, w=0.25) {
    dx = x2-x1; dy = y2-y1;
    L  = sqrt(dx*dx+dy*dy);
    ux = dx/L; uy = dy/L;
    step = dash + gap;
    n = floor(L/step);
    for (i = [0 : n]) {
        t0 = i*step;
        t1 = min(t0+dash, L);
        seg(x1+ux*t0, y1+uy*t0, x1+ux*t1, y1+uy*t1, w, C_CL, Z_CL);
    }
}

// Arrow head (points in +x direction, tip at (ax,ay))
module arrowhead(ax, ay, angle, size=1.8) {
    draw(C_DIM, Z_DIM)
    translate([ax, ay]) rotate([0,0,angle])
        polygon([[0,0], [-size*2.4, size*0.75], [-size*2.4, -size*0.75]]);
}

// Horizontal dimension
module dim_h(x1, x2, y, label, ts=4.0, ext=3.5) {
    mid = (x1+x2)/2;
    draw(C_DIM, Z_DIM) {
        // Extension lines
        square_at(x1-0.15, y-ext, 0.28, ext*2);
        square_at(x2-0.14, y-ext, 0.28, ext*2);
        // Dim line
        square_at(x1+2.2, y-0.14, x2-x1-4.4, 0.28);
    }
    arrowhead(x1+2.2, y,   0, 1.8);
    arrowhead(x2-2.2, y, 180, 1.8);
    draw(C_DIM, Z_TXT)
    translate([mid, y+1.5]) text(label, size=ts, halign="center",
                                  font="Liberation Mono:style=Bold");
}

// Vertical dimension
module dim_v(x, y1, y2, label, ts=4.0, ext=3.5) {
    mid = (y1+y2)/2;
    draw(C_DIM, Z_DIM) {
        square_at(x-ext, y1-0.14, ext*2, 0.28);
        square_at(x-ext, y2-0.14, ext*2, 0.28);
        square_at(x-0.14, y1+2.2, 0.28, y2-y1-4.4);
    }
    arrowhead(x, y1+2.2,  90, 1.8);
    arrowhead(x, y2-2.2, 270, 1.8);
    draw(C_DIM, Z_TXT)
    translate([x-1.5, mid]) rotate([0,0,90])
        text(label, size=ts, halign="center",
             font="Liberation Mono:style=Bold");
}

// Helper: place a square by x,y,w,h (already in draw context)
module square_at(x, y, w, h) {
    translate([x, y]) square([max(0,w), max(0,h)]);
}

// Callout bubble (numbered)
module callout(cx, cy, n, r=4.2) {
    draw(C_PAPER, Z_DIM-0.02) translate([cx,cy]) circle(r=r+0.6);
    draw(C_LINE,  Z_DIM) translate([cx,cy]) difference() {
        circle(r=r);
        circle(r=r-0.55);
    }
    draw(C_TXT, Z_TXT)
    translate([cx - (n>=10 ? r*0.52 : r*0.30), cy - r*0.35])
        text(str(n), size=r*0.82,
             font="Liberation Sans:style=Bold");
}

// Leader line + callout
module leader_call(x1, y1, x2, y2, n) {
    seg(x1, y1, x2, y2, 0.28, C_LINE, Z_DIM-0.01);
    callout(x2, y2, n);
}

// Diagonal hatch fill (section cut indicator)
module hatch(x, y, w, h, sp=2.2, ang=45) {
    translate([x, y, Z_HATCH]) color(C_HATCH) linear_extrude(DH)
    intersection() {
        square([w, h]);
        for (i = [-(w+h)/sp : (w+h)/sp])
            translate([i*sp, 0]) rotate([0,0,ang]) square([0.22, w+h+10]);
    }
}

// ── VIEW BORDER ────────────────────────────────────────────
module view_border(x, y, w, h, title, ts=4.5) {
    // Border
    draw(C_BORD, Z_LINE) translate([x,y]) difference() {
        square([w,h]);
        translate([0.5,0.5]) square([w-1,h-1]);
    }
    // View label at top
    draw(C_TTXT, Z_TXT) translate([x + w/2, y+h+1.5])
        text(title, size=ts, halign="center",
             font="Liberation Sans:style=Bold Italic");
}

// ── SHEET BACKGROUND ───────────────────────────────────────
draw(C_PAPER, -0.1) square([560, 240]);

// Outer border
draw(C_BORD, Z_LINE) difference() {
    square([560, 240]);
    translate([3,3]) square([554,234]);
}

// ── TITLE BLOCK ────────────────────────────────────────────
// Bottom strip: y=0 to y=42
module title_block() {
    // Main border
    draw(C_BORD, Z_LINE) {
        // Outer rect
        translate([3,3]) difference() {
            square([554,36]);
            translate([0.5,0.5]) square([553,35]);
        }
        // Vertical dividers
        translate([3+370, 3]) square([0.5, 36]);
        translate([3+440, 3]) square([0.5, 36]);
        translate([3+494, 3]) square([0.5, 36]);
        // Horizontal divider in right section
        translate([3+370, 3+18]) square([184, 0.5]);
    }
    // Title
    draw(C_TTXT, Z_TXT) {
        translate([190, 28])
            text("LEGO AI SORTING MACHINE v4 HYBRID",
                 size=8, halign="center",
                 font="Liberation Sans:style=Bold");
        translate([190, 19])
            text("Engineering Drawing — Hybrid Mechanical Overview",
                 size=5, halign="center",
                 font="Liberation Sans");
        translate([190, 10])
            text("Frame: 420×140×500 mm   PETG + 2020 Extrusion   Fasteners: M5",
                 size=4, halign="center", font="Liberation Mono");
    }
    // Fields
    draw(C_TTXT, Z_TXT) {
        translate([382, 30]) text("SCALE", size=3.5, font="Liberation Sans:style=Bold");
        translate([382, 22]) text("1 : 4",   size=5.5, font="Liberation Mono:style=Bold");
        translate([382, 13]) text("2026-03", size=3.5, font="Liberation Mono");

        translate([452, 30]) text("SHEET",   size=3.5, font="Liberation Sans:style=Bold");
        translate([452, 22]) text("01/01",   size=5,   font="Liberation Mono");
        translate([452, 13]) text("REV v4.0",size=3.5, font="Liberation Mono");

        translate([506, 30]) text("DRAWN",   size=3.5, font="Liberation Sans:style=Bold");
        translate([506, 22]) text("AI+Human",size=3.5, font="Liberation Mono");
        translate([506, 13]) text("UNITS: mm",size=3.5,font="Liberation Mono");
    }
}

title_block();

// ── COMPONENT LEGEND (right side) ──────────────────────────
LX = 310;   // legend x start
LY = 52;    // legend y start
LH = 5.5;   // line height

module legend() {
    items = [
        [1, "Aluminium 2020 Extrusion Frame"],
        [2, "Step Feeder Hopper (vibratory)"],
        [3, "Carousel Hub (NEMA 17 drive)"],
        [4, "Carousel Arm × 4"],
        [5, "Platform Tray (90×90mm, acrylic insert)"],
        [6, "SG90 Tilt Servo (1 per platform)"],
        [7, "Scanning Chamber (168×120mm)"],
        [8, "Pi Camera Module 3"],
        [9, "LED Strip (dual, top of chamber)"],
        [10,"Pancake Stack (8 levels, Ø180mm)"],
        [11,"Central Rotating Chute"],
        [12,"Chute Drive Stepper + Worm Gear"],
        [13,"Mini Gate Tree (3 lvl, 7 servos)"],
        [14,"Output Bins (8×)"],
        [15,"Electronics Enclosure (RPi 5)"],
        [16,"PCA9685 Servo Driver (×2)"],
    ];

    draw(C_TTXT, Z_TXT)
    translate([LX, LY + len(items)*LH + 4])
        text("COMPONENTS", size=5.5,
             font="Liberation Sans:style=Bold");

    seg(LX, LY + len(items)*LH + 2,
        LX + 240, LY + len(items)*LH + 2, 0.5);

    for (i = [0:len(items)-1]) {
        item = items[len(items)-1-i];
        n = item[0];
        lbl = item[1];
        cy = LY + i*LH + LH/2;

        callout(LX + 4.5, cy, n, 3.8);
        draw(C_TXT, Z_TXT)
        translate([LX + 11, cy - 1.8])
            text(lbl, size=3.8, font="Liberation Sans");
    }
}

legend();

// ============================================================
// ── MAIN VIEW: FRONT ELEVATION (cross-section) ─────────────
// ============================================================
// Machine cut at Y=70 (centre), looking from front (+Y direction)
// Machine X → sheet x = MX + x*S
// Machine Z → sheet y = MZ + z*S
//
// All drawing coords in mm (1:4 scale)
// ============================================================

// View border
view_border(MX-5, MZ-8, 105*S*4+10, 500*S+16,
            "FRONT ELEVATION — CROSS SECTION A-A (1:4)");

// ── Frame ──────────────────────────────────────────────────
// Left upright (x=0, w=20mm)
frect(mx(0),   mz(0),   20*S, 500*S, C_FRAME);
// Right upright (x=400, w=20mm)
frect(mx(400), mz(0),   20*S, 500*S, C_FRAME);
// Horizontal rails (z=0,200,240,480 — 20mm high)
for (zr = [0, 200, 240, 480])
    frect(mx(0), mz(zr), 420*S, 20*S, C_FRAME);
// Short Y-crossmember at belt level
frect(mx(0),   mz(200), 20*S, 40*S, C_FRAME);
frect(mx(400), mz(200), 20*S, 40*S, C_FRAME);

hatch(mx(0),   mz(0),   20*S, 500*S);
hatch(mx(400), mz(0),   20*S, 500*S);
hatch(mx(0),   mz(0),   420*S, 20*S);
hatch(mx(0),   mz(480), 420*S, 20*S);

// ── Step Feeder Hopper ─────────────────────────────────────
frect(mx(22), mz(350), 98*S, 100*S, C_STEP, 0.30);
// Hopper funnel (narrowing)
draw(C_STEP, Z_FILL)
polygon([[mx(22),  mz(350+100)],
         [mx(120), mz(350+100)],
         [mx(82),  mz(350)],
         [mx(60),  mz(350)]]);
draw(C_LINE, Z_LINE)
polygon([[mx(22),  mz(350+100)],
         [mx(120), mz(350+100)],
         [mx(82),  mz(350)],
         [mx(60),  mz(350)],
         [mx(22),  mz(350+100)]]);
// Output chute from hopper
frect(mx(60), mz(300), 22*S, 52*S, C_STEP, 0.28);

// ── Electronics box ────────────────────────────────────────
frect(mx(10), mz(260), 90*S, 80*S, C_ELEC, 0.30);
hatch(mx(10), mz(260), 90*S, 80*S, 2.8, -45);
// PCB inside
frect(mx(18), mz(275), 57*S, 3*S, [0.1,0.6,0.1], 0.20);
// Vent slots
for (zv = [275, 295, 315])
    frect(mx(9), mz(zv), 2*S, 3*S, C_FRAME, 0.15);

// ── Carousel ───────────────────────────────────────────────
// Hub at x=210, z=300
fcirc(mx(210), mz(300), 22*S, C_CAR, 0.35);
fcirc(mx(210), mz(300),  4*S, C_FRAME, 0.25);  // shaft bore

// 4 arms (only two visible from front: left and right)
// Left arm: extends to x=95 (210-115)
frect(mx(95),  mz(297), 115*S, 14*S, C_CAR, 0.28);
// Right arm: extends to x=325 (210+115)
frect(mx(211), mz(297), 114*S, 14*S, C_CAR, 0.28);
// Vertical arm (toward us / away from us)
frect(mx(203), mz(297), 14*S, 14*S, C_CAR, 0.28);

// Platforms at arm tips — 4 shown (left, right, towards, away)
// Left platform at x=95-5 → x=48..68 (in front)
frect(mx(50),  mz(305), 90*S, 10*S, C_PLAT, 0.28);  // top view shows this
frect(mx(277), mz(305), 90*S, 10*S, C_PLAT, 0.28);  // right arm platform
// Dispensing platform (at left, x=95) tilted — show angled
draw(C_PLAT, Z_FILL)
polygon([[mx(52),  mz(303)],
         [mx(52+90*S), mz(303)],
         [mx(52+90*S), mz(303+4)],
         [mx(52),       mz(303+10)]]);
draw(C_LINE, Z_LINE)
polygon([[mx(52),  mz(303)],
         [mx(52+90*S), mz(303)],
         [mx(52+90*S), mz(303+4)],
         [mx(52),       mz(303+10)],
         [mx(52),  mz(303)]]);

// ── Scanning Chamber ───────────────────────────────────────
frect(mx(140), mz(218), 168*S, 128*S, C_COMP, 0.30);
// Hollow interior
draw(C_PAPER, Z_FILL+0.02)
translate([mx(144), mz(222)]) square([160*S, 122*S]);
// LED strips top
frect(mx(144), mz(340), 160*S, 4*S, [1,1,0.5], 0.20);
// Camera (black circle at top)
fcirc(mx(224), mz(358), 17.5*S, C_CAM, 0.30);
fcirc(mx(224), mz(362), 10*S, [0.0, 0.2, 0.8], 0.20);
// Entry/exit slots (darker gap)
frect(mx(140), mz(218), 8*S, 60*S, [0.6,0.6,0.6], 0.20);
frect(mx(300), mz(218), 8*S, 60*S, [0.6,0.6,0.6], 0.20);

// ── Pancake Stack ──────────────────────────────────────────
// 8 levels, each 55mm tall, 180mm diam, centred at x=95
NUM_LVLS = 8;
LVL_H    = 34;
OUTER_R  = 90;

for (i = [0:NUM_LVLS-1]) {
    zb = 30 + i*LVL_H;
    // Outer ring
    frect(mx(95-OUTER_R), mz(zb), OUTER_R*2*S, LVL_H*S, C_STACK, 0.25);
    // Hollow interior (chute passage)
    draw(C_PAPER, Z_FILL+0.01)
    translate([mx(95-46), mz(zb+3)]) square([92*S, (LVL_H-3)*S]);
    // Bin mouth (opening) alternates left/right visually
    mouth_x = (i % 2 == 0) ? mx(95+46) : mx(95-OUTER_R);
    draw(C_PAPER, Z_FILL+0.01)
    translate([mouth_x, mz(zb+2)]) square([44*S, (LVL_H-4)*S]);
    // Level separator line
    seg(mx(95-OUTER_R), mz(zb), mx(95+OUTER_R), mz(zb), 0.28);
}
// Top cap
frect(mx(95-OUTER_R), mz(30+NUM_LVLS*LVL_H), OUTER_R*2*S, 4*S, C_STACK, 0.25);

// Central chute tube
frect(mx(95-46), mz(25), 92*S, (30+NUM_LVLS*LVL_H+4-25)*S, C_CAR, 0.28);
draw(C_PAPER, Z_FILL+0.01)
translate([mx(95-43), mz(27)]) square([86*S, (30+NUM_LVLS*LVL_H+2-27)*S]);

// 80mm sphere constraint annotation circle at top of stack
draw([0.9,0.2,0.2], Z_LINE) translate([mx(95), mz(30+NUM_LVLS*LVL_H+15)])
    difference() {
        circle(r=40*S, $fn=64);
        circle(r=39*S, $fn=64);
    }
seg(mx(95-40), mz(30+NUM_LVLS*LVL_H+15), mx(95+40), mz(30+NUM_LVLS*LVL_H+15),
    0.25, [0.9,0.2,0.2], Z_DIM);  // diameter line
draw([0.9,0.2,0.2], Z_TXT) translate([mx(95)-2, mz(30+NUM_LVLS*LVL_H+15)+1])
    text("Ø80", size=3.8, halign="center", font="Liberation Mono:style=Bold");

// ── Mini Gate Tree ─────────────────────────────────────────
// 3 levels: z=120-175, z=65-120, z=10-65 (simplified)
gate_levels = [[150,60,130],[100,50,105],[50,38,90]]; // [z_bot, sz, num_x_centre]

// Level 0 root
frect(mx(175), mz(128), 70*S, 60*S, C_GATE, 0.28);
// Level 1
frect(mx(150), mz(70), 50*S, 56*S, C_GATE, 0.28);
frect(mx(245), mz(70), 50*S, 56*S, C_GATE, 0.28);
// Level 2
for (gx = [130, 182, 230, 278])
    frect(mx(gx), mz(15), 40*S, 52*S, C_GATE, 0.25);
// Connecting chutes
for (gx = [155, 247]) seg(mx(gx+2), mz(70), mx(gx+2), mz(128), 0.5, C_GATE, Z_LINE);
for (gx = [135, 187, 234, 282]) seg(mx(gx+2), mz(15), mx(gx+2), mz(70), 0.4, C_GATE, Z_LINE);

// Output bins (8 × below gate tree)
for (i = [0:7])
    frect(mx(118 + i*28), mz(-25), 22*S, 24*S, C_BIN, 0.25);

// ── CENTERLINES ────────────────────────────────────────────
// Vertical machine centreline x=210
dline(mx(210), mz(-30), mx(210), mz(510));
// Carousel arm horizontal
dline(mx(80),  mz(300), mx(345), mz(300));
// Pancake stack centreline
dline(mx(95), mz(-30), mx(95), mz(302));
// Scanning chamber centreline
dline(mx(224), mz(215), mx(224), mz(380));

// ── DIMENSION LINES ────────────────────────────────────────
// Overall width: 420mm
dim_h(mx(0), mx(420), mz(520), "420", 5.0);
// Overall height: 500mm
dim_v(mx(430), mz(0), mz(500), "500", 5.0);
// Carousel height: z=300
dim_v(mx(445), mz(0), mz(300), "300", 4.2);
// Stack height: 8×34=272
dim_v(mx(-18), mz(30), mz(30+8*34), "272", 4.2);
// Stack outer diameter: 180mm
dim_h(mx(95-90), mx(95+90), mz(20), "Ø180", 4.2);
// Scanning chamber width: 168mm
dim_h(mx(140), mx(308), mz(356), "168", 4.2);
// Carousel reach: 210±115
dim_h(mx(95), mx(325), mz(316), "230", 4.2);
// Platform size: 90mm
dim_h(mx(50), mx(50+90*S/S), mz(290), "90", 4.0);

// ── CALLOUT LEADERS ────────────────────────────────────────
leader_call(mx(210), mz(480), mx(258), mz(495), 1);   // Frame
leader_call(mx(70),  mz(400), mx(270), mz(412), 2);   // Step feeder
leader_call(mx(210), mz(300), mx(258), mz(315), 3);   // Carousel hub
leader_call(mx(165), mz(304), mx(258), mz(330), 4);   // Arm
leader_call(mx(100), mz(308), mx(258), mz(348), 5);   // Platform
leader_call(mx(100), mz(296), mx(258), mz(366), 6);   // Tilt servo
leader_call(mx(224), mz(346), mx(258), mz(382), 7);   // Scanning chamber
leader_call(mx(224), mz(362), mx(258), mz(400), 8);   // Camera
leader_call(mx(144), mz(340), mx(258), mz(418), 9);   // LED
leader_call(mx(95),  mz(200), mx(258), mz(436), 10);  // Pancake stack
leader_call(mx(95),  mz(150), mx(258), mz(454), 11);  // Central chute
leader_call(mx(210), mz(100), mx(258), mz(472), 13);  // Mini gate tree
leader_call(mx(135), mz(-10), mx(185), mz(-22), 14);  // Bins
leader_call(mx(55),  mz(300), mx(258), mz(282), 15);  // Electronics

// ── SECTION CUT INDICATOR (A-A) ────────────────────────────
// Cutting plane line above and below view
seg(mx(-15), mz(-5),  mx(-15), mz(505),  0.6, C_BORD, Z_DIM);
seg(mx(435), mz(-5),  mx(435), mz(505),  0.6, C_BORD, Z_DIM);
draw(C_TXT, Z_TXT) { translate([mx(-15)-3, mz(505)+3]) text("A", size=6, halign="right", font="Liberation Sans:style=Bold"); }
draw(C_TXT, Z_TXT) { translate([mx(-15)-3, mz(-5)-8])  text("A", size=6, halign="right", font="Liberation Sans:style=Bold"); }
draw(C_TXT, Z_TXT) { translate([mx(435)+1,  mz(505)+3]) text("A", size=6, font="Liberation Sans:style=Bold"); }
draw(C_TXT, Z_TXT) { translate([mx(435)+1,  mz(-5)-8])  text("A", size=6, font="Liberation Sans:style=Bold"); }

// ============================================================
// ── PLAN VIEW (TOP VIEW) INSET ─────────────────────────────
// Looking straight down (–Z direction)
// Machine X → sheet x, Machine Y → sheet y
// ============================================================

PV_LABEL_Y = PY + 140*S + 12;

view_border(PX-5, PY-6, 420*S+10, 140*S+12,
            "PLAN VIEW — TOP (1:4)");

// Frame footprint
frect(px(0),   py(0),   20*S, 140*S, C_FRAME);
frect(px(400), py(0),   20*S, 140*S, C_FRAME);
frect(px(0),   py(0),   420*S, 20*S, C_FRAME);
frect(px(0),   py(120), 420*S, 20*S, C_FRAME);

hatch(px(0),   py(0),   20*S, 140*S);
hatch(px(400), py(0),   20*S, 140*S);
hatch(px(0),   py(0),   420*S, 20*S);
hatch(px(0),   py(120), 420*S, 20*S);

// Carousel — circle at x=210, y=70, r=115mm arm reach
draw(C_CAR, Z_FILL) translate([px(210), py(70)]) circle(r=115*S, $fn=64);
draw(C_PAPER, Z_FILL+0.01) translate([px(210), py(70)]) circle(r=113*S, $fn=64);
// Hub
fcirc(px(210), py(70), 22*S, C_CAR, 0.30);
// Arms (4 directions)
for (a = [0, 90, 180, 270]) {
    ax = cos(a); ay = sin(a);
    // Arm shaft
    seg(px(210 + ax*22), py(70 + ay*22),
        px(210 + ax*102), py(70 + ay*102),
        11*S, C_CAR, Z_LINE);
    // Platform square
    frect(px(210 + ax*105 - 45*S), py(70 + ay*105 - 45*S), 90*S, 90*S, C_PLAT, 0.25);
}

// Pancake stack circle at x=95, y=70
draw(C_STACK, Z_FILL) translate([px(95), py(70)]) circle(r=90*S, $fn=64);
draw(C_PAPER, Z_FILL+0.01) translate([px(95), py(70)]) circle(r=88*S, $fn=64);
// Inner chute
fcirc(px(95), py(70), 46*S, C_CAR, 0.25);
draw(C_PAPER, Z_FILL+0.01) translate([px(95), py(70)]) circle(r=44*S, $fn=64);

// Step feeder
frect(px(22), py(30), 98*S, 80*S, C_STEP, 0.28);

// Mini gate tree
frect(px(130), py(35), 190*S, 70*S, C_GATE, 0.28);
draw(C_PAPER, Z_FILL+0.01) translate([px(133), py(38)]) square([184*S, 64*S]);

// Electronics
frect(px(10), py(25), 90*S, 100*S, C_ELEC, 0.28);

// Scanning chamber
frect(px(140), py(15), 168*S, 130*S, C_COMP, 0.28);
draw(C_PAPER, Z_FILL+0.01) translate([px(144), py(19)]) square([160*S, 122*S]);

// Centrelines on plan view
dline(px(210), py(-8), px(210), py(148));  // carousel centre
dline(px(95),  py(-8), px(95),  py(148));  // stack centre
dline(px(-10), py(70), px(430), py(70));   // machine centreline

// Dimension: frame depth 140mm
dim_v(px(-12), py(0), py(140), "140", 4.2);
// Carousel reach 230mm
dim_h(px(95), px(325), py(148), "230", 4.2);
// Stack diameter 180mm
dim_h(px(5),  px(185), py(-12), "Ø180", 4.0);
// Scanning chamber depth 130mm
dim_v(px(313), py(15), py(145), "130", 4.0);

// C_BIN convenience
C_BIN = [0.92, 0.62, 0.20];
