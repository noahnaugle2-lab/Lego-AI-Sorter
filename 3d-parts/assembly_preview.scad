// ============================================================
// LEGO AI Sorting Machine — Full Assembly Preview
// ============================================================
// Composite scene showing all major subsystems in approximate
// assembled position. Used to render the README hero image.
// ============================================================

$fn = 48;

// ── COLOURS ────────────────────────────────────────────────
C_FRAME      = [0.55, 0.55, 0.55];   // silver aluminium extrusion
C_CHAMBER    = [0.95, 0.95, 0.95];   // white PLA scanning chamber
C_BELT       = [0.15, 0.15, 0.15];   // dark rubber belt
C_ROLLER     = [0.2,  0.5,  1.0];    // blue PETG rollers
C_GATE       = [0.2,  0.7,  0.4];    // green gate modules
C_SERVO      = [0.3,  0.3,  0.3];    // dark servo bodies
C_ELECTRONICS= [0.3,  0.5,  0.9];    // blue electronics box
C_CAMERA     = [0.1,  0.1,  0.1];    // black camera
C_LED        = [1.0,  1.0,  0.6];    // warm LED glow
C_BIN        = [0.9,  0.6,  0.2];    // orange bins
C_BRACKET    = [0.6,  0.6,  0.6];    // grey brackets

// ── FRAME ─────────────────────────────────────────────────
// 2020 aluminium extrusion skeleton (simplified rectangles)
module extrusion(len, axis="x") {
    color(C_FRAME)
    if (axis == "x")      cube([len, 20, 20]);
    else if (axis == "y") cube([20, len, 20]);
    else                  cube([20, 20, len]);
}

module frame() {
    // Four vertical uprights
    for (x = [0, 400]) for (y = [0, 120])
        translate([x, y, 0]) extrusion(500, "z");

    // Bottom horizontal rails (front & back, left & right)
    translate([0,   0,   0]) extrusion(420, "x");
    translate([0, 120,   0]) extrusion(420, "x");
    translate([0,   0, 480]) extrusion(420, "x");
    translate([0, 120, 480]) extrusion(420, "x");

    // Mid-height cross rails
    translate([0,   0, 240]) extrusion(420, "x");
    translate([0, 120, 240]) extrusion(420, "x");
    translate([0,   0, 240]) extrusion(140, "y");
    translate([400, 0, 240]) extrusion(140, "y");

    // Belt support rails
    translate([0,   0, 200]) extrusion(420, "x");
    translate([0, 120, 200]) extrusion(420, "x");
    translate([0,  20, 200]) extrusion(100, "y");
    translate([390, 20, 200]) extrusion(100, "y");
}

// ── CONVEYOR BELT ─────────────────────────────────────────
module belt_system() {
    // Belt surface
    color(C_BELT)
    translate([20, 30, 218]) cube([360, 80, 4]);

    // Drive roller
    color(C_ROLLER)
    translate([15, 30, 200])
        rotate([0, 90, 0]) cylinder(h=80, d=25);

    // Idler roller
    color(C_ROLLER)
    translate([375, 30, 200])
        rotate([0, 90, 0]) cylinder(h=80, d=25);

    // Tensioner bracket (simplified block)
    color(C_BRACKET)
    translate([5, 35, 195]) cube([12, 70, 30]);
}

// ── SCANNING CHAMBER ─────────────────────────────────────
// Positioned above belt at centre of frame
module scanning_chamber() {
    // Outer box (translucent so internals visible)
    color(C_CHAMBER, 0.5)
    translate([140, 15, 218])
        difference() {
            cube([168, 148, 128]);
            // Belt slot openings
            translate([-1, 24, 8]) cube([10, 90, 60]);
            translate([159, 24, 8]) cube([10, 90, 60]);
            // Interior hollow
            translate([4, 4, 4]) cube([160, 140, 130]);
        }

    // LED strip glow (thin strip along top interior)
    color(C_LED, 0.9)
    translate([144, 19, 338]) cube([160, 4, 4]);
    translate([144, 151, 338]) cube([160, 4, 4]);

    // Camera (black cylinder on top)
    color(C_CAMERA)
    translate([224, 89, 350]) cylinder(h=18, d=35);
    // lens
    color([0.0, 0.2, 0.8], 0.7)
    translate([224, 89, 366]) cylinder(h=4, d=20);
}

// ── GATE TREE ─────────────────────────────────────────────
// 5-level binary tree of Y-junction gate modules
// Positioned below belt on the right half of the frame
module one_gate(sz) {
    color(C_GATE, 0.85)
    cube([sz, 55, 60]);
    // Servo body
    color(C_SERVO)
    translate([sz/2-12, 40, 20]) cube([24, 13, 23]);
    // Gate flap
    color([0.9, 0.9, 0.9])
    translate([sz/2-30, 28, 24]) cube([60, 2, 20]);
}

module gate_tree() {
    // Level 0 — 1 gate (root), 70mm wide
    translate([200, 35, 150]) one_gate(70);

    // Level 1 — 2 gates, ~80mm wide each
    for (x = [155, 255])
        translate([x, 35, 90]) one_gate(55);

    // Level 2 — 4 gates
    for (x = [130, 195, 240, 295])
        translate([x, 35, 35]) one_gate(42);

    // Chutes between levels (thin slabs)
    color(C_GATE, 0.5) {
        // L1→L2 chutes
        translate([170, 38, 90]) cube([4, 49, 60]);
        translate([262, 38, 90]) cube([4, 49, 60]);
        // L0→L1 chutes
        translate([200, 38, 148]) cube([4, 49, 60]);
        translate([270, 38, 148]) cube([4, 49, 60]);
    }

    // Output bins (level 3 — 8 simplified boxes)
    for (i = [0:7]) {
        color(C_BIN, 0.8)
        translate([115 + i*28, 30, -30])
            cube([24, 80, 30]);
    }
}

// ── ELECTRONICS BOX ───────────────────────────────────────
module electronics_box() {
    color(C_ELECTRONICS, 0.9)
    translate([10, 25, 260]) cube([90, 100, 80]);
    // Vent slots
    color(C_FRAME)
    for (z = [275, 295, 315])
        translate([9, 35, z]) cube([2, 80, 3]);
    // Raspberry Pi green PCB (inside)
    color([0.1, 0.6, 0.1])
    translate([18, 35, 275]) cube([57, 56, 3]);
}

// ── BELT SIDE RAILS ───────────────────────────────────────
module side_rails() {
    color([0.85, 0.85, 0.85])
    translate([20, 22, 218]) cube([360, 3, 15]);
    color([0.85, 0.85, 0.85])
    translate([20, 115, 218]) cube([360, 3, 15]);
}

// ── FULL ASSEMBLY ─────────────────────────────────────────
frame();
belt_system();
scanning_chamber();
gate_tree();
electronics_box();
side_rails();

// ── LABEL (comment out if not wanted) ─────────────────────
// No text — keeping purely 3D for render clarity
