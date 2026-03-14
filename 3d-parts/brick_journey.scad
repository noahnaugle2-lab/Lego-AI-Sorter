// ============================================================
// LEGO AI Sorting Machine — Brick Journey Animation
// Parametric frame driven by $t  (0.0 → 1.0)
//
// Stages (by $t):
//   0.00 – 0.18  Brick travels along belt towards chamber
//   0.18 – 0.30  Brick inside chamber, camera flash
//   0.30 – 0.42  Brick exits chamber, continues belt
//   0.42 – 0.55  Brick drops off belt end into gate tree
//   0.55 – 0.72  Gates actuate (root → level 2)
//   0.72 – 0.88  Brick falls through gate tree
//   0.88 – 1.00  Brick lands in output bin
// ============================================================

$fn = 36;

// ── HELPERS ────────────────────────────────────────────────
function lerp(a, b, t) = a + (b - a) * t;
function clamp(v, lo, hi) = max(lo, min(hi, v));
function remap(t, t0, t1) = clamp((t - t0) / (t1 - t0), 0, 1);

// ── COLOURS ────────────────────────────────────────────────
C_FRAME   = [0.55, 0.55, 0.55];
C_BELT    = [0.15, 0.15, 0.15];
C_ROLLER  = [0.2,  0.5,  1.0];
C_CHAMBER = [0.95, 0.95, 0.95];
C_CAM     = [0.1,  0.1,  0.1];
C_LED     = [1.0,  1.0,  0.5];
C_GATE    = [0.2,  0.7,  0.4];
C_SERVO   = [0.3,  0.3,  0.3];
C_ELEC    = [0.3,  0.5,  0.9];
C_BIN     = [0.9,  0.6,  0.2];
C_BRICK   = [0.95, 0.15, 0.15];  // bright red LEGO brick
C_FLASH   = [1.0,  1.0,  0.8];

// ── ANIMATION STATE ────────────────────────────────────────
// FRAME_T is set via -D on the command line (0.0 → 1.0)
FRAME_T = 0;   // default; overridden per frame
t = FRAME_T;

// Belt travel:  brick x goes from 30 → 390 (belt start to end)
// Camera flash: stage 0.18–0.30
// Gate actuation and brick drop happen after belt end

// Brick on belt (stages 0.0 → 0.42)
belt_t    = remap(t, 0.0, 0.42);
brick_bx  = lerp(30, 390, belt_t);   // x along belt
brick_bz  = 222;                      // sitting on belt surface

// Is brick in chamber? (x roughly 140–310, t 0.12–0.34)
in_chamber = (t >= 0.14 && t <= 0.36) ? 1 : 0;

// Flash intensity
flash_t   = remap(t, 0.18, 0.22);
flash_fade= remap(t, 0.26, 0.30);
flash     = clamp(flash_t - flash_fade, 0, 1);

// Brick drop from belt into gate tree (t 0.42 → 0.55)
drop_t    = remap(t, 0.42, 0.55);
brick_dx  = lerp(390, 290, drop_t);   // slides right to gate root x
brick_dz  = lerp(222, 160, drop_t);   // falls from belt to root gate

// Brick in gate tree (t 0.55 → 0.88)
// Route: root → right branch → right-right bin (bin 7)
fall_t    = remap(t, 0.55, 0.88);
brick_gx  = lerp(290, 310, fall_t);   // slight x drift right
brick_gz  = lerp(160, -20, fall_t);   // falls through tree to bins

// Final position in bin
in_bin    = t >= 0.88 ? 1 : 0;

// Brick position selector
brick_x = t < 0.42 ? brick_bx :
          t < 0.55 ? brick_dx :
          t < 0.88 ? brick_gx : 310;

brick_z = t < 0.42 ? brick_bz :
          t < 0.55 ? brick_dz :
          t < 0.88 ? brick_gz : -20;

// ── GATE ANGLES ────────────────────────────────────────────
// Gates actuate when brick approaches (t 0.55–0.72)
// Root gate rotates right (brick goes right)
gate0_t   = remap(t, 0.55, 0.63);
gate0_ang = lerp(0, 35, gate0_t);   // root flap angle

gate1_t   = remap(t, 0.63, 0.70);
gate1_ang = lerp(0, 35, gate1_t);   // level-1 right gate

gate2_t   = remap(t, 0.70, 0.76);
gate2_ang = lerp(0, 35, gate2_t);   // level-2 right-right gate

// ── FRAME ──────────────────────────────────────────────────
module extrusion(len, axis="x") {
    color(C_FRAME)
    if (axis == "x")      cube([len, 20, 20]);
    else if (axis == "y") cube([20, len, 20]);
    else                  cube([20, 20, len]);
}

module frame() {
    for (x = [0, 400]) for (y = [0, 120])
        translate([x, y, 0]) extrusion(500, "z");
    translate([0,   0,   0]) extrusion(420, "x");
    translate([0, 120,   0]) extrusion(420, "x");
    translate([0,   0, 480]) extrusion(420, "x");
    translate([0, 120, 480]) extrusion(420, "x");
    translate([0,   0, 240]) extrusion(420, "x");
    translate([0, 120, 240]) extrusion(420, "x");
    translate([0,   0, 200]) extrusion(420, "x");
    translate([0, 120, 200]) extrusion(420, "x");
    translate([0,   0, 240]) extrusion(140, "y");
    translate([400, 0, 240]) extrusion(140, "y");
    translate([0,  20, 200]) extrusion(100, "y");
    translate([390,20, 200]) extrusion(100, "y");
}

module belt_system() {
    color(C_BELT)   translate([20, 30, 218]) cube([360, 80, 4]);
    color(C_ROLLER) translate([15, 30, 200]) rotate([0,90,0]) cylinder(h=80,d=25);
    color(C_ROLLER) translate([375,30,200]) rotate([0,90,0]) cylinder(h=80,d=25);
    // side rails
    color([0.8,0.8,0.8]) translate([20, 22,218]) cube([360,3,15]);
    color([0.8,0.8,0.8]) translate([20,115,218]) cube([360,3,15]);
}

module scanning_chamber() {
    // Flash: brighten chamber interior when camera fires
    ci = lerp(0.7, 1.0, flash);
    color(C_CHAMBER, 0.55)
    translate([140, 15, 218])
        difference() {
            cube([168, 148, 128]);
            translate([-1, 24, 8]) cube([10, 90, 60]);
            translate([159,24, 8]) cube([10, 90, 60]);
            translate([4,  4,  4]) cube([160,140,130]);
        }
    // LED strips
    color([ci, ci, lerp(0.5,1.0,flash)], 0.9)
    translate([144, 19, 338]) cube([160, 4, 4]);
    color([ci, ci, lerp(0.5,1.0,flash)], 0.9)
    translate([144,151, 338]) cube([160, 4, 4]);
    // Camera
    color(C_CAM)   translate([224, 89, 350]) cylinder(h=18, d=35);
    color([0.0,0.2,0.8+flash*0.2], 0.7+flash*0.3)
    translate([224, 89, 366]) cylinder(h=4, d=20);
}

module electronics_box() {
    color(C_ELEC, 0.9) translate([10, 25, 260]) cube([90,100,80]);
    color([0.1,0.6,0.1])  translate([18, 35, 275]) cube([57,56,3]);
    color(C_FRAME)
    for (z=[275,295,315]) translate([9,35,z]) cube([2,80,3]);
}

// One gate module with animated flap
module gate_module(gx, gz, flap_angle, sz=70) {
    // Body
    color(C_GATE, 0.85) translate([gx-sz/2, 35, gz]) cube([sz, 55, 60]);
    // Servo
    color(C_SERVO) translate([gx-12, 70, gz+20]) cube([24,13,23]);
    // Animated flap
    color([0.9,0.9,0.9])
    translate([gx, 57, gz+29])
        rotate([0, flap_angle, 0])
            translate([-30, 0, -2])
                cube([60, 2, 4]);
}

module gate_tree() {
    gate_module(210, 140, gate0_ang, 70);  // root
    gate_module(170,  85, gate1_ang, 55);  // L1 left
    gate_module(265,  85, gate1_ang, 55);  // L1 right
    gate_module(145,  30, gate2_ang, 42);  // L2 ll
    gate_module(195,  30, gate2_ang, 42);  // L2 lr
    gate_module(240,  30, gate2_ang, 42);  // L2 rl
    gate_module(295,  30, gate2_ang, 42);  // L2 rr

    // Output bins
    for (i = [0:7])
        color(C_BIN, 0.85)
        translate([115 + i*28, 30, -30]) cube([24, 80, 30]);
}

// ── BRICK ──────────────────────────────────────────────────
module lego_brick(bx, bz) {
    // Body
    color(C_BRICK)
    translate([bx-16, 45, bz]) cube([32, 32, 19]);
    // Studs (2×2)
    color(C_BRICK)
    for (sx=[-8,8], sy=[51,63])
        translate([bx+sx, sy, bz+19]) cylinder(h=4, d=9);
}

// ── TRAIL (motion blur dots) ───────────────────────────────
module trail() {
    if (t < 0.42) {
        for (i=[1:4]) {
            trail_t = clamp(belt_t - i*0.04, 0, 1);
            tx = lerp(30, 390, trail_t);
            color(C_BRICK, (5-i)*0.1)
            translate([tx-16, 45, brick_bz]) cube([32,32,19]);
        }
    }
}

// ── RENDER ─────────────────────────────────────────────────
frame();
belt_system();
scanning_chamber();
electronics_box();
gate_tree();
trail();
lego_brick(brick_x, brick_z);
