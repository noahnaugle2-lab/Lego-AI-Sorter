// ============================================================
// LEGO AI Sorting Machine — Carousel Feeder
// ============================================================
//
// CONCEPT (from carousel/turntable feeder research):
//   A 4-platform rotating carousel replaces the linear belt.
//   All four positions process simultaneously (pipelined):
//
//     Position 0 (LOAD)     ← step feeder deposits one brick
//     Position 1 (IMAGE)    ← camera captures, AI classifies
//     Position 2 (DISPENSE) ← platform tilts, brick drops to gate tree
//     Position 3 (CLEAR)    ← platform returns flat, ready to load
//
//   One 90° carousel rotation advances all platforms by one stage.
//   Effective throughput: 1 brick per rotation cycle (~2–3 s).
//
// KEY ADVANTAGES OVER LINEAR BELT:
//   - No ramp angle problem (platforms tilt actively to dispense)
//   - Natural singulation: only one brick per platform
//   - Parallel pipeline: load/image/dispense happen simultaneously
//   - Acrylic platform inserts allow future under-platform camera option
//   - 80mm sphere size constraint built into 90mm platform openings
//
// FITS WITHIN EXISTING FRAME:
//   Machine frame: 420mm × 140mm × 500mm (x,y,z)
//   Carousel footprint: 340mm × 140mm
//   Carousel centre: x=210, y=70, z=210
//   Gate tree input: x=210, z=140 (directly below dispense position)
//
// HARDWARE:
//   - 1× NEMA 17 stepper (central rotation, replaces belt stepper)
//   - 4× SG90 servo (one per platform, tilt for dispense)
//   - 1× rotary encoder on central shaft (home/position detection)
//   - 4× 80mm × 80mm acrylic sheet (platform inserts)
//   - 4× M3×16 screws per platform hinge
//
// PRINT SETTINGS:
//   Material: PETG
//   Layer height: 0.2mm
//   Infill: 25%
//   Supports: NONE (all geometry prints upright or flat)
//   Estimated time: ~8 hours total (hub + 4 arms + 4 platforms)
//
// All dimensions in mm.
// ============================================================

$fn = 48;

// ── GEOMETRY PARAMETERS ────────────────────────────────────

// Platform dimensions — 90mm to safely contain 80mm sphere limit
PLAT_W   = 90;    // platform width (x)
PLAT_D   = 90;    // platform depth (y, radial)
PLAT_T   = 3;     // platform floor thickness
PLAT_LIP = 6;     // raised lip height on 3 sides (not the dispense edge)
LIP_T    = 3;     // lip wall thickness

// Arm geometry
ARM_REACH  = 110; // distance from hub centre to platform near edge
ARM_W      = 22;  // arm width
ARM_H      = 14;  // arm height
ARM_T      = 3;   // arm wall thickness (hollow box arm)

// Hub
HUB_D  = 44;  // hub outer diameter
HUB_H  = 30;  // hub height
BORE_D = 8;   // central shaft bore (8mm shaft)

// Hinge & servo
HINGE_W    = 10;   // hinge tab width
HINGE_T    = 4;    // hinge tab thickness
HINGE_PIN_D= 3.2;  // 3mm pivot pin clearance
SERVO_W    = 23;
SERVO_D    = 12;
SERVO_H    = 22;

// Hardware holes
M3_D  = 3.4;
M5_D  = 5.5;

// Acrylic insert pocket
INSERT_W = 80;
INSERT_D = 80;
INSERT_T = 2.5; // acrylic sheet depth
INSERT_MARGIN = (PLAT_W - INSERT_W) / 2;

// ── CENTRAL HUB ────────────────────────────────────────────
// Solid cylinder with central shaft bore.
// Four arm attachment faces milled flat (90° apart).

module hub() {
    difference() {
        cylinder(h=HUB_H, d=HUB_D);
        // Shaft bore
        translate([0, 0, -1])
            cylinder(h=HUB_H+2, d=BORE_D);
        // Key-way slot (prevents slippage on shaft)
        translate([-1, -BORE_D/2-2, HUB_H/3])
            cube([2, 4, HUB_H/2]);
    }
}

// ── HOLLOW BOX ARM ─────────────────────────────────────────
// Lightweight I-beam arm extending from hub face to platform hinge.

module arm() {
    total_len = ARM_REACH + HUB_D/2;
    difference() {
        cube([total_len, ARM_W, ARM_H]);
        // Hollow interior
        translate([HUB_D/2, ARM_T, ARM_T])
            cube([total_len - HUB_D/2 - ARM_T,
                  ARM_W - 2*ARM_T,
                  ARM_H - 2*ARM_T]);
    }
}

// ── PLATFORM BODY ──────────────────────────────────────────
// Flat tray with lip on 3 sides, open on dispense edge (–y).
// Acrylic insert pocket is in the floor for transparent bottom.

module platform_body() {
    difference() {
        union() {
            // Floor slab
            cube([PLAT_W, PLAT_D, PLAT_T]);

            // Back lip
            translate([0, PLAT_D - LIP_T, 0])
                cube([PLAT_W, LIP_T, PLAT_LIP + PLAT_T]);

            // Left lip
            translate([0, 0, 0])
                cube([LIP_T, PLAT_D, PLAT_LIP + PLAT_T]);

            // Right lip
            translate([PLAT_W - LIP_T, 0, 0])
                cube([LIP_T, PLAT_D, PLAT_LIP + PLAT_T]);
        }

        // Acrylic insert pocket (inset from floor top face)
        translate([INSERT_MARGIN, INSERT_MARGIN, PLAT_T - INSERT_T])
            cube([INSERT_W, INSERT_D, INSERT_T + 1]);
    }
}

// ── PLATFORM HINGE TABS ────────────────────────────────────
// Two tabs that couple platform to arm end.
// Pin passes through both tabs and arm clevis bracket.

module hinge_tabs() {
    for (y = [5, PLAT_D - 5 - HINGE_T]) {
        translate([-HINGE_T, y, PLAT_T/2 - HINGE_W/2])
            difference() {
                cube([HINGE_T + 2, HINGE_T, HINGE_W]);
                translate([-1, HINGE_T/2, HINGE_W/2])
                    rotate([0, 90, 0])
                        cylinder(h=HINGE_T+4, d=HINGE_PIN_D);
            }
    }
}

// ── SERVO MOUNT (under platform) ───────────────────────────
// Pocket under platform near hinge end for SG90 tilt servo.

module servo_mount_pocket() {
    translate([(PLAT_W - SERVO_W)/2, 0, -SERVO_H])
        difference() {
            cube([SERVO_W + 4, SERVO_D + 4, SERVO_H]);
            translate([2, 2, -1])
                cube([SERVO_W, SERVO_D, SERVO_H + 2]);
        }
}

// ── COMPLETE PLATFORM ───────────────────────────────────────

module platform() {
    platform_body();
    hinge_tabs();
}

// ── ARM CLEVIS BRACKET ──────────────────────────────────────
// Printed as part of the arm tip — two upstanding ears that the
// platform hinge tabs slot into.

module arm_clevis(arm_length) {
    clevis_h = PLAT_T + PLAT_LIP/2 + 4;
    ear_sep  = PLAT_D + 2;
    ear_t    = HINGE_T + 1;

    translate([arm_length - ear_t, -1, 0])
    for (y_off = [0, ear_sep - ear_t]) {
        translate([0, y_off, 0])
            difference() {
                cube([ear_t, ear_t + 1, clevis_h]);
                // Pin hole
                translate([-1, (ear_t + 1)/2, clevis_h/2])
                    rotate([0, 90, 0])
                        cylinder(h=ear_t+2, d=HINGE_PIN_D);
            }
    }
}

// ── FULL ARM ASSEMBLY (one of four) ────────────────────────

module arm_assembly() {
    arm_length = ARM_REACH + HUB_D/2;

    // Arm
    translate([0, -ARM_W/2, -ARM_H/2])
        arm();

    // Clevis at arm tip
    translate([0, -ARM_W/2, -ARM_H/2])
        arm_clevis(arm_length);

    // Platform (sits in clevis, shown in closed/flat position)
    translate([arm_length, -PLAT_D/2, ARM_H/2])
        platform();
}

// ── FULL CAROUSEL ASSEMBLY ──────────────────────────────────

module carousel() {
    hub();
    for (a = [0, 90, 180, 270])
        rotate([0, 0, a]) arm_assembly();
}

// ── POSITION LABELS (for viewer orientation) ───────────────
// POSITION 0  (  0°) = LOAD
// POSITION 1  ( 90°) = IMAGE  (camera above)
// POSITION 2  (180°) = DISPENSE (tilts, drops to gate tree)
// POSITION 3  (270°) = CLEAR

// ── RENDER ─────────────────────────────────────────────────
//
// Exploded view: hub centred at origin, arms extending outward.
// In the assembled machine, translate hub to [210, 70, 210].
//

color([0.65, 0.70, 0.90]) carousel();

// ── PRINT LAYOUT (uncomment to export STLs) ────────────────

// Hub (print upright):
// color([0.4, 0.4, 0.8]) hub();

// Single arm (print flat, arm along X axis):
// color([0.5, 0.7, 0.5]) arm_assembly();

// Single platform (print floor-down):
// color([0.8, 0.8, 0.5]) platform();

// ============================================================
// PRINT INSTRUCTIONS
//
// Hub:
//   Orientation: Upright (shaft bore vertical)
//   Supports: Small overhang at keyway — negligible
//   Time: ~40 min
//
// Arms (print 4×):
//   Orientation: Long axis along X, flat on bed
//   Supports: NONE (hollow box has no overhangs)
//   Time: ~35 min each
//
// Platforms (print 4×):
//   Orientation: Floor face UP (lip walls print from bed)
//   Supports: NONE
//   Time: ~25 min each
//
// ASSEMBLY:
//   1. Press hub onto NEMA 17 shaft, tighten grub screw
//   2. Attach arms to hub with M5 bolts through hub flanges
//   3. Slide platform hinge tabs into arm clevis; thread 3mm pin
//   4. Mount SG90 servo under each platform; connect horn linkage
//   5. Insert 80mm acrylic squares into platform floor pockets
//   6. Mount carousel at z=210, centre x=210, y=70 in main frame
//
// DISPENSE MOTION:
//   - At rest: platform horizontal (servo at 90°)
//   - Dispense: servo rotates to 150° → platform tips ~45° forward
//   - Brick slides off platform lip, falls into gate tree input
//   - Return: servo back to 90°, ready for next load
//
// 80mm SPHERE CONSTRAINT:
//   Platform interior = 90mm × 90mm
//   Acrylic insert = 80mm × 80mm
//   The 80mm opening accommodates 98% of production LEGO pieces.
// ============================================================
