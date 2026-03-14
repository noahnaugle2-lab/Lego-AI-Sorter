// ============================================================
// LEGO AI Sorting Machine — Pancake Stack Distribution Tower
// ============================================================
//
// CONCEPT (from pancake stack bin research):
//   Stacked circular bins share a central rotating chute.
//   One servo per level rotates the chute to point at that
//   level's bin opening; a trap-door at the bottom of the
//   chute then opens to release the brick.
//
//   This replaces (or supplements) the binary gate tree:
//
//     Gate tree: 31 servos → 32 bins  (binary routing)
//     Pancake stack: N servos → N bins  (direct addressing)
//
//   For ≤18 bins the pancake stack uses fewer servos and
//   less vertical height than a 5-level binary tree.
//
// STACKING GEOMETRY:
//   Each level is a circular disc with:
//     - One 100° arc opening (the active "bin mouth")
//     - A shallow tray floor
//     - 3× snap-lock posts to the level above
//   Levels interlock without screws; a single M5 rod through
//   the centre tie-rod holds the whole stack.
//
// CENTRAL CHUTE:
//   - Hollow cylinder, 90mm inner diameter (80mm sphere constraint)
//   - Rotates on a central bearing (608 skateboard bearing)
//   - Driven by one small stepper + worm gear at the base
//   - An acrylic window lets the camera verify chute angle
//
// DIMENSIONS (8 bins, fits in existing 500mm frame height):
//   Bin count    : 8
//   Level height : 55mm (fits large 2×4 brick + clearance)
//   Total height : 8 × 55 = 440mm
//   Outer diameter: 260mm
//   Inner chute ID: 90mm
//   Centre offset : fits at x=210, y=70 in machine frame
//
// HARDWARE PER LEVEL:
//   - 1× SG90 servo (or equivalent micro servo)
//   - 1× printed chute director (rotates to select bin mouth)
//   - 1× 608 bearing at centre
//
// All dimensions in mm.
// ============================================================

$fn = 48;

// ── PARAMETERS ─────────────────────────────────────────────

NUM_LEVELS     = 8;          // number of bins
LEVEL_H        = 55;         // height of each bin level
OUTER_R        = 130;        // outer radius of bin disc
INNER_R        = 48;         // inner radius (chute channel)
WALL_T         = 3;          // wall thickness
FLOOR_T        = 4;          // bin floor thickness
MOUTH_ANG      = 100;        // arc angle of bin opening (degrees)
CHUTE_OR       = INNER_R;    // chute tube outer radius
CHUTE_IR       = 45;         // chute inner radius (brick passage)
SNAP_W         = 8;
SNAP_H         = 5;
SNAP_D         = 2;
SNAP_N         = 3;          // snap posts per level
M5_D           = 5.5;        // centre tie-rod hole

// Colours
C_BIN   = [0.90, 0.62, 0.20];
C_CHUTE = [0.40, 0.60, 0.90];
C_SERVO = [0.30, 0.30, 0.30];
C_BEAR  = [0.70, 0.70, 0.70];

// ── BIN DISC (one level) ───────────────────────────────────
// A hollow disc with one arc opening as the bin mouth.
// Three snap posts on top connect to the level above.

module bin_disc(mouth_start_ang = 0) {
    // Body ring
    difference() {
        union() {
            // Outer wall
            difference() {
                cylinder(h=LEVEL_H, r=OUTER_R);
                translate([0, 0, -1])
                    cylinder(h=LEVEL_H+2, r=OUTER_R - WALL_T);
            }
            // Floor
            difference() {
                translate([0, 0, 0])
                    cylinder(h=FLOOR_T, r=OUTER_R);
                translate([0, 0, -1])
                    cylinder(h=FLOOR_T+2, r=INNER_R);
                // Centre tie-rod clearance
                cylinder(h=FLOOR_T+2, d=M5_D);
            }
            // Inner wall (chute collar)
            difference() {
                cylinder(h=LEVEL_H, r=INNER_R);
                translate([0, 0, -1])
                    cylinder(h=LEVEL_H+2, r=INNER_R - WALL_T);
            }
        }

        // Bin mouth opening (arc cut in outer wall)
        rotate([0, 0, mouth_start_ang])
            rotate_extrude(angle=MOUTH_ANG)
                translate([OUTER_R - WALL_T - 1, 0])
                    square([WALL_T + 4, LEVEL_H - FLOOR_T + 1]);

        // Sloped floor toward mouth (encourages brick to slide out)
        rotate([0, 0, mouth_start_ang + MOUTH_ANG/2])
            rotate([0, -10, 0])
                translate([-OUTER_R, -OUTER_R, 0])
                    cube([2*OUTER_R, 2*OUTER_R, FLOOR_T]);
    }

    // Snap posts on top (plug into slots of level above)
    for (a = [0 : 360/SNAP_N : 360 - 1])
        rotate([0, 0, a + mouth_start_ang + MOUTH_ANG + 20])
            translate([OUTER_R - WALL_T - 4, 0, LEVEL_H])
                cube([SNAP_W, SNAP_D, SNAP_H], center=true);
}

// ── CHUTE DIRECTOR ─────────────────────────────────────────
// Hollow tube that rotates inside the inner collar.
// An angled nozzle at the bottom directs brick to the correct mouth.

module chute_director() {
    // Main tube
    difference() {
        cylinder(h=NUM_LEVELS * LEVEL_H + 20, r=CHUTE_OR - WALL_T - 1);
        translate([0, 0, -1])
            cylinder(h=NUM_LEVELS * LEVEL_H + 22, r=CHUTE_IR);
        // Centre tie-rod
        cylinder(h=NUM_LEVELS * LEVEL_H + 22, d=M5_D);
    }

    // Angled exit nozzle at bottom
    translate([0, 0, 0])
        rotate([0, 20, 0])
            difference() {
                cylinder(h=60, r=CHUTE_OR - WALL_T - 1);
                translate([0, 0, -1])
                    cylinder(h=62, r=CHUTE_IR - 2);
            }
}

// ── BEARING SEAT ────────────────────────────────────────────
// 608 skateboard bearing (22mm OD, 8mm ID, 7mm wide)
// Seats at the top of the chute director.

module bearing_seat() {
    BEAR_OD = 22; BEAR_ID = 8; BEAR_W = 7;
    difference() {
        cylinder(h=BEAR_W + 4, d=BEAR_OD + 6);
        translate([0, 0, 2])
            cylinder(h=BEAR_W + 2, d=BEAR_OD + 0.4);
        cylinder(h=BEAR_W + 5, d=BEAR_ID + 0.4);
    }
}

// ── SERVO MOUNT RING ────────────────────────────────────────
// Sits at the base; one servo drives chute rotation via worm gear.

module servo_mount_ring() {
    ring_h = 40; SV_W = 23; SV_D = 12; SV_H = 30;
    difference() {
        cylinder(h=ring_h, r=INNER_R + WALL_T);
        // Centre passage
        translate([0, 0, -1])
            cylinder(h=ring_h+2, r=INNER_R - WALL_T);
        // Servo pocket
        translate([INNER_R - SV_D/2, -SV_W/2, 5])
            cube([SV_D + 4, SV_W, SV_H]);
    }
}

// ── COMPLETE STACK ──────────────────────────────────────────

module pancake_stack() {
    // Servo drive base
    color(C_SERVO) servo_mount_ring();

    // Stacked bin levels — each rotated so mouth faces a different direction
    for (i = [0 : NUM_LEVELS - 1]) {
        mouth_ang = i * (360 / NUM_LEVELS);
        color(C_BIN, 0.88)
            translate([0, 0, i * LEVEL_H])
                bin_disc(mouth_ang);
    }

    // Chute director (central rotating tube)
    color(C_CHUTE, 0.80)
        translate([0, 0, -5])
            chute_director();

    // Bearing seat at top
    color(C_BEAR)
        translate([0, 0, NUM_LEVELS * LEVEL_H])
            bearing_seat();
}

// ── RENDER ─────────────────────────────────────────────────

pancake_stack();

// ── SINGLE LEVEL (uncomment to export STL) ─────────────────

// Single bin disc (print flat on bed, floor face down):
// color(C_BIN) bin_disc(0);

// Chute director (print upright):
// color(C_CHUTE) chute_director();

// Bearing seat (print upright):
// color(C_BEAR) bearing_seat();

// ============================================================
// HOW IT WORKS (SOFTWARE):
//
//   1. AI classifies brick → determines target bin (0–7)
//   2. Calculate chute angle = target_bin × 45° (360/8)
//   3. Rotate chute director to that angle (stepper motor)
//   4. Confirm angle via encoder
//   5. Open trap-door at chute exit (one solenoid/servo)
//   6. Brick falls down chute, exits at correct level mouth
//   7. Gravity carries brick into bin tray
//
// ROUTING COMPARISON:
//
//   Binary gate tree (existing):
//     32 bins, 31 servos, 5 decisions, complex wiring
//     Vertical drop = ~200mm (fast, clean)
//
//   Pancake stack (this design):
//     8–18 bins, N servos, 1 decision, simple wiring
//     Vertical drop = level_index × 55mm (up to 385mm for bin 7)
//
//   HYBRID RECOMMENDATION:
//     Use pancake stack for primary sort (8 colour/category bins)
//     Feed overflow to secondary gate tree for sub-sorting
//     This halves the gate tree to 3 levels (7 servos, 8 sub-bins)
//     Total: 8 + 8 = up to 64 unique sort destinations
//
// PRINT INSTRUCTIONS:
//
// Bin Disc (print 8×):
//   Orientation: Floor face DOWN on print bed
//   Supports: NONE (outer wall is vertical; mouth is a simple cut)
//   Time: ~40 min each
//
// Chute Director (print 1×):
//   Orientation: Upright (tube vertical)
//   Supports: Minor at nozzle angle (~45°), or orient horizontally
//   Time: ~60 min
//
// Servo Mount Ring (print 1×):
//   Orientation: Flat base on bed
//   Supports: NONE
//   Time: ~30 min
//
// TOTAL PRINT TIME: ~8 hours (8 discs + chute + servo ring)
// MATERIAL: PETG recommended (low friction for brick sliding)
// ============================================================
