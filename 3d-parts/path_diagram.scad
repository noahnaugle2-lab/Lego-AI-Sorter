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

// ── PATH WAYPOINTS ─────────────────────────────────────────
//  A (30,  224) start on belt
//  B (224, 224) under camera
//  C (310, 224) exit chamber
//  D (390, 224) belt end → drop
//  E (245, 163) gate root
//  F (268, 113) gate L1
//  G (291,  55) gate L2
//  H (307,   0) bin

module path() {
    // Belt segments
    arr( 30, 224, 134, 224);
    arr(150, 224, 215, 224);
    arr(233, 224, 302, 224);
    arr(318, 224, 382, 224);

    // Camera scan beam (down from camera to brick)
    arr(224, 348, 224, 238);

    // Drop off belt
    arr(385, 218, 254, 170);

    // Through gate tree
    arr(248, 160, 264, 120);
    arr(266, 112, 286,  63);
    arr(288,  52, 305,   8);

    // Stage dots
    dot( 30, 224);
    dot(224, 224);
    dot(390, 224);
    dot(245, 163);
    dot(307,   0);

    // Brick at start position
    brick(30, 224);
}

// ── ASSEMBLE ───────────────────────────────────────────────
frame_cs();
belt_cs();
chamber_cs();
electronics_cs();
gate_cs();
bins_cs();
path();
