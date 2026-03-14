// ============================================================
// LEGO AI Sorting Machine — Hybrid Assembly Preview
// ============================================================
//
// Composite scene showing the HYBRID v4 design:
//
//   INPUT:        Carousel Feeder (4-platform rotating carousel)
//                 replaces the linear conveyor belt
//
//   SCANNER:      Fixed scanning chamber above carousel position 1
//                 (unchanged from v3)
//
//   DISTRIBUTION: Pancake Stack Tower (8 bins) as primary sorter
//                 + mini 3-level gate tree (8 sub-bins) for
//                 secondary sorting = up to 64 destinations
//
// COORDINATE SYSTEM (same as all other v3 .scad files):
//   X = left↔right (0 = left, 420 = right)
//   Y = front↔back (0 = front, 140 = back)
//   Z = up (0 = floor, 500 = top)
//
// ============================================================

$fn = 48;

// ── COLOURS ────────────────────────────────────────────────
C_FRAME    = [0.55, 0.55, 0.55];
C_CAROUSEL = [0.55, 0.65, 0.90];
C_PLAT     = [0.85, 0.85, 0.60];
C_CHAMBER  = [0.95, 0.95, 0.95];
C_CAM      = [0.10, 0.10, 0.10];
C_LED      = [1.00, 1.00, 0.60];
C_STACK    = [0.90, 0.62, 0.20];
C_CHUTE    = [0.40, 0.60, 0.90];
C_GATE     = [0.20, 0.70, 0.40];
C_SERVO    = [0.30, 0.30, 0.30];
C_ELEC     = [0.30, 0.50, 0.90];
C_BIN      = [0.90, 0.62, 0.20];
C_STEP     = [0.60, 0.50, 0.40];   // step feeder hopper

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
    for (z = [0, 200, 240, 480]) {
        translate([0,   0, z]) extrusion(420, "x");
        translate([0, 120, z]) extrusion(420, "x");
    }
    translate([0,  0, 240]) extrusion(140, "y");
    translate([400,0, 240]) extrusion(140, "y");
}

// ── STEP FEEDER HOPPER ─────────────────────────────────────
// Vibrating hopper that singulates bricks one at a time.
// Mounted at top-left of frame; drops bricks onto carousel pos-0.

module step_feeder() {
    color(C_STEP, 0.85) {
        // Main hopper body (truncated pyramid)
        hull() {
            translate([20, 30, 420]) cube([100, 80, 4]);
            translate([60, 50, 340]) cube([40, 40, 4]);
        }
        // Output chute
        translate([60, 50, 300]) cube([40, 40, 44]);
        // Vibration motor boss (small cylinder on side)
        translate([65, 30, 380])
            rotate([90, 0, 0])
                cylinder(h=6, d=18);
    }
}

// ── CAROUSEL FEEDER ────────────────────────────────────────
// Simplified representation: hub + 4 arms + 4 platforms.
// Centred at x=210, y=70, z=300.

CAROUSEL_CX = 210;
CAROUSEL_CY = 70;
CAROUSEL_CZ = 300;  // hub centre height

ARM_R   = 115;  // arm reach (hub centre to platform centre)
PLAT_S  = 90;   // platform side length

module carousel_platform(tilt=0) {
    rotate([tilt, 0, 0])
    color(C_PLAT, 0.90) {
        cube([PLAT_S, PLAT_S, 3], center=true);
        // Lip on 3 sides
        for (face = [[0, -(PLAT_S/2+1.5), 4],
                     [-(PLAT_S/2+1.5), 0, 4],
                     [ (PLAT_S/2+1.5), 0, 4]])
            translate([face[0], face[1], face[2]])
                cube([PLAT_S-2, 3, 6], center=true);
    }
}

module carousel() {
    translate([CAROUSEL_CX, CAROUSEL_CY, CAROUSEL_CZ]) {
        // Hub
        color(C_CAROUSEL) cylinder(h=30, d=44, center=true);

        // 4 arms at 0°, 90°, 180°, 270°
        // 0° = LOAD (brick drops from step feeder)
        // 90° = IMAGE (under camera)
        // 180° = DISPENSE (drops to pancake stack)
        // 270° = CLEAR

        for (a = [0, 90, 180, 270]) {
            rotate([0, 0, a]) {
                // Arm
                color(C_CAROUSEL)
                    translate([22, -11, -5])
                        cube([ARM_R - 22, 22, 10]);

                // Platform
                translate([ARM_R, 0, 12]) {
                    // Tilt dispensing platform at 180° for illustration
                    tilt_ang = (a == 180) ? -35 : 0;
                    carousel_platform(tilt_ang);

                    // Servo under platform
                    color(C_SERVO)
                        translate([-11, -12, -22])
                            cube([23, 12, 22]);
                }
            }
        }
    }
}

// ── SCANNING CHAMBER ───────────────────────────────────────
// Centred over carousel position 1 (90° arm, image position).
// Position 1 arm points in +X direction → platform at x=210+115, y=70.

SCAN_CX = 210;   // camera looks straight down at carousel centre
SCAN_CY = 0;     // front of chamber flush with frame front rail
SCAN_CZ = CAROUSEL_CZ + 15;

module scanning_chamber() {
    color(C_CHAMBER, 0.50)
    translate([SCAN_CX - 84, SCAN_CY + 15, SCAN_CZ])
        difference() {
            cube([168, 120, 120]);
            // Openings on bottom for carousel arm clearance
            translate([4, 4, -1]) cube([160, 112, 30]);
            // Interior hollow
            translate([4, 4, 28]) cube([160, 112, 92]);
        }

    // LED strips
    color(C_LED, 0.9)
        translate([SCAN_CX - 80, SCAN_CY + 17, SCAN_CZ + 112])
            cube([160, 4, 3]);

    // Camera
    color(C_CAM)
        translate([SCAN_CX, SCAN_CY + 75, SCAN_CZ + 122])
            cylinder(h=18, d=35);
    color([0.0, 0.2, 0.8], 0.7)
        translate([SCAN_CX, SCAN_CY + 75, SCAN_CZ + 138])
            cylinder(h=4, d=20);
}

// ── PANCAKE STACK ──────────────────────────────────────────
// 8-level distribution tower.
// Positioned below carousel dispense position (180° arm):
// Dispense arm at a=180° → platform at x=210-115 = 95, y=70.

STACK_CX = 95;
STACK_CY = 70;
STACK_Z0 = 30;   // base of stack (sits on lower frame rail)

NUM_LEVELS = 8;
LEVEL_H    = 34;
OUTER_R    = 90;
INNER_R    = 48;

module stack_level(i) {
    mouth_ang = i * (360 / NUM_LEVELS);
    color(C_STACK, 0.85)
    difference() {
        cylinder(h=LEVEL_H, r=OUTER_R);
        // Hollow interior
        translate([0, 0, 3])
            cylinder(h=LEVEL_H, r=OUTER_R - 3);
        // Floor hole (inner chute)
        cylinder(h=LEVEL_H + 2, r=INNER_R);
        // Mouth opening
        rotate([0, 0, mouth_ang])
            rotate_extrude(angle=100)
                translate([OUTER_R - 5, 0])
                    square([6, LEVEL_H - 2]);
    }
}

module pancake_stack() {
    translate([STACK_CX, STACK_CY, STACK_Z0]) {
        for (i = [0 : NUM_LEVELS - 1])
            translate([0, 0, i * LEVEL_H])
                stack_level(i);

        // Central chute tube
        color(C_CHUTE, 0.75)
            difference() {
                cylinder(h=NUM_LEVELS * LEVEL_H + 20, r=INNER_R - 1);
                translate([0, 0, -1])
                    cylinder(h=NUM_LEVELS * LEVEL_H + 22, r=INNER_R - 4);
            }
    }
}

// ── MINI GATE TREE (3 levels, 8 sub-bins) ──────────────────
// Secondary sorter under the pancake stack.
// Takes overflow from any stack level and sub-sorts into 8 bins.
// This is a simplified visual representation.

module mini_gate(cx, cz, sz=50) {
    color(C_GATE, 0.85)
        translate([cx - sz/2, 30, cz])
            cube([sz, 55, 48]);
    color(C_SERVO)
        translate([cx - 10, 62, cz + 14])
            cube([20, 11, 20]);
}

module mini_gate_tree() {
    // Level 0 — 1 root gate
    mini_gate(300, 120, 60);
    // Level 1 — 2 gates
    for (cx = [268, 335]) mini_gate(cx, 70, 50);
    // Level 2 — 4 gates
    for (cx = [248, 285, 315, 355]) mini_gate(cx, 25, 38);

    // 8 output bins
    for (i = [0:7])
        color(C_BIN, 0.80)
            translate([238 + i*18, 30, -20])
                cube([14, 70, 22]);
}

// ── ELECTRONICS BOX ────────────────────────────────────────
module electronics_box() {
    color(C_ELEC, 0.90)
        translate([10, 25, 260]) cube([90, 100, 80]);
    color(C_FRAME)
    for (z = [275, 295, 315])
        translate([9, 35, z]) cube([2, 80, 3]);
    color([0.1, 0.6, 0.1])
        translate([18, 35, 275]) cube([57, 56, 3]);
}

// ── ASSEMBLE ───────────────────────────────────────────────

frame();
step_feeder();
carousel();
scanning_chamber();
pancake_stack();
mini_gate_tree();
electronics_box();

// ============================================================
// HYBRID DESIGN PHILOSOPHY
//
// This "v4 Hybrid" takes the best from two designs:
//
//   FROM v3 (existing):
//     ✓ Binary gate tree routing algorithm (sorter.py)
//     ✓ Brickognize AI classifier + local HSV cache
//     ✓ Flask dashboard + SQLite inventory
//     ✓ Confidence-based routing (review/unknown bins)
//     ✓ Scanning chamber with top-mounted Pi Camera Module 3
//
//   FROM blog design:
//     ✓ Carousel feeder — replaces linear belt, solves:
//         - Singulation (one brick per platform, no jamming)
//         - Ramp angle problem (tilt-to-dispense, no ramp needed)
//         - Parallel pipeline (load/image/process/dispense simultaneous)
//     ✓ 80mm sphere constraint — all openings sized to 90mm interior
//     ✓ Pancake stack — primary sort by category (8 bins, 8 servos)
//         simpler than 31-servo tree for category-level sorting
//     ✓ Step feeder — singulates from bulk hopper
//
//   RETAINED + ADAPTED:
//     ✓ Mini gate tree (3 levels) for sub-sorting within a category
//     ✓ Dual-stage sorting: pancake (category) → mini-tree (part)
//     ✓ Same Python API — only conveyor.py and sorter.py need updates
//
// ============================================================
