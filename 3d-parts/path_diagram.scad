// ============================================================
// LEGO AI Sorting Machine — Cross-Section Path Diagram
// Machine is cut along the centre (Y = 70) to reveal the
// interior. The brick's journey is traced with red arrows.
// ============================================================

$fn = 48;
CUT_Y = 42;

C_FRAME   = [0.50, 0.52, 0.54];
C_BELT    = [0.18, 0.18, 0.18];
C_ROLLER  = [0.25, 0.50, 0.95];
C_CHAMBER = [0.88, 0.92, 0.96];
C_CAM     = [0.10, 0.10, 0.10];
C_LED     = [1.00, 0.95, 0.55];
C_GATE    = [0.20, 0.68, 0.38];
C_SERVO   = [0.28, 0.28, 0.28];
C_ELEC    = [0.28, 0.48, 0.88];
C_PCB     = [0.10, 0.55, 0.15];
C_BIN     = [0.90, 0.60, 0.18];
C_RAIL    = [0.78, 0.78, 0.78];
C_ARROW   = [0.95, 0.12, 0.12];
C_CUTFACE = [0.72, 0.76, 0.80];

// ── CLIP: keeps only y >= CUT_Y ────────────────────────────
module clip() {
    intersection() {
        children();
        translate([-200, CUT_Y, -200]) cube([900, 500, 900]);
    }
}

// ── FRAME ──────────────────────────────────────────────────
module frame_cs() {
    color(C_FRAME) clip() union() {
        for (x = [0, 400]) for (y = [0, 140])
            translate([x, y, 0]) cube([20, 20, 500]);
        for (z = [0, 200, 240, 480]) {
            translate([0,   0, z]) cube([420, 20, 20]);
            translate([0, 140, z]) cube([420, 20, 20]);
        }
        translate([0,   20, 200]) cube([20, 100, 20]);
        translate([400, 20, 200]) cube([20, 100, 20]);
    }
}

// ── BELT ───────────────────────────────────────────────────
module belt_cs() {
    color(C_BELT) clip()
        translate([20, 30, 218]) cube([360, 80, 4]);

    color(C_ROLLER) clip() union() {
        translate([15,  30, 200]) rotate([0,90,0]) cylinder(h=80, d=25);
        translate([375, 30, 200]) rotate([0,90,0]) cylinder(h=80, d=25);
    }

    color(C_RAIL) clip() union() {
        translate([20,  22, 218]) cube([360, 3, 15]);
        translate([20, 115, 218]) cube([360, 3, 15]);
    }
}

// ── SCANNING CHAMBER ───────────────────────────────────────
module chamber_cs() {
    color(C_CHAMBER, 0.82) clip()
        difference() {
            translate([140, 15, 218]) cube([168, 148, 128]);
            translate([139, 24, 218]) cube([10, 90, 62]);
            translate([299, 24, 218]) cube([10, 90, 62]);
            translate([144, 19, 222]) cube([160, 140, 122]);
        }

    color(C_LED) clip() union() {
        translate([144,  19, 340]) cube([160, 4, 4]);
        translate([144, 147, 340]) cube([160, 4, 4]);
    }

    color(C_CAM) clip()
        translate([224, 89, 350]) cylinder(h=20, d=35);

    color([0.05, 0.20, 0.80], 0.85) clip()
        translate([224, 89, 368]) cylinder(h=4, d=20);
}

// ── ELECTRONICS BOX ────────────────────────────────────────
module electronics_cs() {
    color(C_ELEC, 0.90) clip()
        translate([10, 25, 260]) cube([90, 100, 80]);

    color(C_PCB) clip()
        translate([18, 35, 275]) cube([57, 56, 3]);

    color(C_FRAME) clip() union() {
        for (z = [275, 295, 315])
            translate([9, 35, z]) cube([2, 80, 3]);
    }
}

// ── GATE TREE ──────────────────────────────────────────────
module gate_cs() {
    gates = [
        [210, 140, 70],
        [170,  85, 55],
        [265,  85, 55],
        [145,  30, 42],
        [195,  30, 42],
        [240,  30, 42],
        [295,  30, 42],
    ];
    for (g = gates) {
        cx = g[0]; cz = g[1]; sz = g[2];
        color(C_GATE, 0.88) clip()
            translate([cx-sz/2, 35, cz]) cube([sz, 55, 58]);
        color(C_SERVO) clip()
            translate([cx-12, 68, cz+20]) cube([24, 13, 22]);
        color([0.92, 0.92, 0.92]) clip()
            translate([cx, 57, cz+28]) rotate([0, 20, 0])
                translate([-28, 0, -2]) cube([56, 3, 4]);
    }
}

// ── OUTPUT BINS ────────────────────────────────────────────
module bins_cs() {
    for (i = [0:7])
        color(C_BIN, 0.88) clip()
            translate([115 + i*28, 30, -32]) cube([24, 80, 30]);
}

// ── CUT FACE (shows the cross-section plane) ───────────────
module cut_face() {
    color(C_CUTFACE, 0.18)
    translate([-50, CUT_Y - 0.5, -60]) cube([560, 1, 560]);
}

// ── ARROWS ─────────────────────────────────────────────────
AY = CUT_Y - 2;   // arrows float just in front of cut face

module seg(x1, z1, x2, z2, r=3.2) {
    dx = x2-x1; dz = z2-z1;
    L  = sqrt(dx*dx + dz*dz);
    a  = atan2(dz, dx);
    color(C_ARROW)
    translate([x1, AY, z1])
        rotate([90, 0, 0])
        rotate([0, 0, -a])
        rotate([0, 90, 0])
            cylinder(h=L, r=r);
}

module tip(x, z, ax, az, hr=8, hh=16) {
    dx = ax-x; dz = az-z;
    L  = sqrt(dx*dx+dz*dz);
    a  = atan2(dz, dx);
    color(C_ARROW)
    translate([x, AY, z])
        rotate([90, 0, 0])
        rotate([0, 0, -a])
        rotate([0, 90, 0])
            cylinder(h=hh, r1=hr, r2=0);
}

// arrow: shaft from (x1,z1) to tip at (x2,z2)
module arr(x1, z1, x2, z2) {
    dx = x2-x1; dz = z2-z1;
    L  = sqrt(dx*dx+dz*dz);
    ux = dx/L; uz = dz/L;
    hh = 16; hr = 8;
    seg(x1, z1, x2-ux*hh, z2-uz*hh);
    tip(x2-ux*hh, z2-uz*hh, x2, z2, hr, hh);
}

// Dot marker (white halo + red fill)
module dot(x, z, r=8) {
    color([1,1,1], 0.95)
    translate([x, AY-1.2, z]) rotate([90,0,0]) cylinder(h=2.5, r=r+3.5, $fn=32);
    color(C_ARROW)
    translate([x, AY-0.8, z]) rotate([90,0,0]) cylinder(h=2.5, r=r, $fn=32);
}

// Brick icon
module brick(x, z) {
    color(C_ARROW)
    translate([x-13, AY-1.5, z]) cube([26, 3, 16]);
    color(C_ARROW)
    for (sx = [-6, 6])
        translate([x+sx, AY-1.5, z+16]) rotate([90,0,0]) cylinder(h=3, d=8, $fn=16);
}

// ── ENTRY CHUTE (clipped cross-section) ───────────────────
C_CHUTE = [0.55, 0.68, 0.92];

module chute_cs() {
    // Ramp floor — thin angled slab from belt exit down to gate throat
    color(C_CHUTE, 0.92) clip() hull() {
        translate([387, 35, 197]) cube([3, 70, 3]);
        translate([248, 35, 197]) cube([3, 70, 3]);
    }
    // Catch wall — vertical plate at belt end (x=390)
    color(C_CHUTE, 0.92) clip()
        translate([390, 35, 197]) cube([3, 70, 25]);
    // Front taper wall
    color(C_CHUTE, 0.80) clip() hull() {
        translate([387, 32, 197]) cube([3, 3, 22]);
        translate([248, 35, 197]) cube([3, 3, 5]);
    }
    // Back taper wall
    color(C_CHUTE, 0.80) clip() hull() {
        translate([387, 105, 197]) cube([3, 3, 22]);
        translate([248, 90, 197]) cube([3, 3, 5]);
    }
    // Throat left wall (guides into gate root from right)
    color(C_CHUTE, 0.92) clip()
        translate([245, 35, 181]) cube([3, 70, 18]);
    // Throat right wall (outer guide)
    color(C_CHUTE, 0.92) clip()
        translate([172, 35, 181]) cube([3, 70, 18]);
}

// ── PATH WAYPOINTS ─────────────────────────────────────────
//  A (30,  224) brick starts on belt (left)
//  B (224, 224) under camera — classification scan
//  C (390, 224) belt end — brick hits catch wall
//  D (390, 210) slides down catch wall onto ramp
//  E (245, 200) ramp exit — enters gate throat
//  F (210, 185) gate root input
//  G (265,  85) gate L1 right branch
//  H (295,  30) gate L2 right-right branch
//  I (307,   0) lands in output bin

module path() {
    // ── Belt: A → B → C ──
    arr( 30, 224, 134, 224);
    arr(150, 224, 215, 224);
    arr(233, 224, 302, 224);
    arr(318, 224, 382, 224);

    // ── Camera scan beam (down from camera) ──
    arr(224, 348, 224, 238);

    // ── Catch wall: brick hits wall, drops down ──
    arr(390, 222, 390, 205);

    // ── Ramp: slides left-and-down to gate throat ──
    arr(388, 202, 252, 200);

    // ── Gate throat: drops into root gate ──
    arr(245, 200, 218, 188);

    // ── Through gate tree ──
    arr(213, 182, 262,  92);
    arr(264,  84, 290,  38);
    arr(292,  30, 305,   4);

    // ── Stage dots ──
    dot( 30, 224);   // start
    dot(224, 224);   // camera scan
    dot(390, 222);   // belt end / catch wall
    dot(245, 200);   // ramp exit / gate throat
    dot(210, 185);   // gate root
    dot(307,   0);   // bin

    // ── Brick icon at start ──
    brick(30, 224);
}

// ── ASSEMBLE ───────────────────────────────────────────────
// Draw chute first so gate modules render on top of it
frame_cs();
chute_cs();
belt_cs();
chamber_cs();
electronics_cs();
gate_cs();
bins_cs();
path();
