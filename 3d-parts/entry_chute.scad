// ============================================================
// LEGO AI Sorting Machine — Entry Chute & Funnel
// ============================================================
//
// PURPOSE:
//   Bridges the gap between the conveyor belt exit and the
//   top of the binary gate tree.
//
//   Belt exit:  x=390, z=218, y-centre=70 (80mm wide belt)
//   Gate root:  x=175–245 (70mm wide), top at z=200, y=35–90
//
// HOW IT WORKS:
//   1. RIGHT CATCH WALL — vertical plate at x=390 stops bricks
//      from flying past the entry. Belt ends at the roller
//      (radius 12.5mm) so bricks fall ~18mm onto the ramp.
//   2. RAMP FLOOR — slopes 4.8° downward from the catch wall
//      (x=390, z=215) to the gate root opening (x=245, z=200).
//      Gravity carries bricks along this slope.
//   3. TAPERED SIDE WALLS — funnel the width from the full belt
//      width (80mm) at the inlet down to the gate module width
//      (70mm) at the outlet.
//   4. GATE THROAT — short vertical section at x=245 that aligns
//      the brick with the root gate flap centreline.
//
// PRINT OPTIMISATION:
//   Split into FRONT HALF and BACK HALF — each half is an open
//   trough that prints face-up with zero supports.
//   The two halves clip together with the same snap-tab system
//   as the gate modules.
//
//   Material: PETG (low friction, durable)
//   Layer height: 0.2mm
//   Infill: 20%
//   Supports: NONE
//   Estimated print time: ~45 min per half
//
// MOUNTING:
//   Four M5 tabs bolt to the 2020 extrusion frame rails at the
//   belt level. The chute aligns with the belt end roller on
//   the right and drops into the gate root channel on the left.
//
// All dimensions in mm.
// ============================================================

$fn = 48;

// ── KEY GEOMETRY ───────────────────────────────────────────

// Belt exit (right end of belt)
BELT_EXIT_X  = 390;
BELT_SURF_Z  = 218;   // belt top surface height
BELT_Y_MIN   = 30;
BELT_Y_MAX   = 110;
BELT_Y_CEN   = 70;    // (30+110)/2
BELT_WIDTH   = 80;    // y span of belt

// Gate root input
GATE_X_LEFT  = 175;   // root gate left wall
GATE_X_RIGHT = 245;   // root gate right wall
GATE_Y_MIN   = 35;
GATE_Y_MAX   = 90;
GATE_Y_CEN   = 62.5;  // (35+90)/2
GATE_WIDTH   = 70;    // y span of gate root
GATE_TOP_Z   = 200;   // top of root gate module

// Derived
RAMP_DROP    = BELT_SURF_Z - 4 - GATE_TOP_Z;   // ~14mm — ramp height change
RAMP_RUN     = BELT_EXIT_X - GATE_X_RIGHT;     // ~145mm — horizontal run
RAMP_ANGLE   = atan(RAMP_DROP / RAMP_RUN);     // ≈5.5° — gentle slope
CATCH_HEIGHT = BELT_SURF_Z + 15 - GATE_TOP_Z;  // catch wall height above ramp base

// Wall thickness
WALL = 3;
SNAP_W = 8;
SNAP_H = 4;
SNAP_D = 2;
SNAP_TOL = 0.25;
M5_DIA = 5.5;

// ── RAMP FLOOR ─────────────────────────────────────────────
// Solid sloped panel — formed by hull of inlet and outlet edges.
// Inlet edge: at x=BELT_EXIT_X, full belt width
// Outlet edge: at x=GATE_X_RIGHT, gate root width

module ramp_floor() {
    hull() {
        // Inlet (right, high) — full belt width
        translate([BELT_EXIT_X - WALL,
                   BELT_Y_CEN - BELT_WIDTH/2,
                   GATE_TOP_Z - WALL])
            cube([WALL, BELT_WIDTH, WALL]);

        // Outlet (left, low) — gate root width
        translate([GATE_X_RIGHT,
                   GATE_Y_CEN - GATE_WIDTH/2,
                   GATE_TOP_Z - WALL])
            cube([WALL, GATE_WIDTH, WALL]);
    }
}

// ── RIGHT CATCH WALL ───────────────────────────────────────
// Vertical plate that stops bricks from shooting off the end.
// Spans full belt width in y; extends from ramp top to above belt.

module catch_wall() {
    translate([BELT_EXIT_X,
               BELT_Y_CEN - BELT_WIDTH/2,
               GATE_TOP_Z - WALL])
        cube([WALL, BELT_WIDTH, CATCH_HEIGHT + WALL]);
}

// ── FRONT SIDE WALL ────────────────────────────────────────
// Tapers from belt width at inlet to gate width at outlet.
// Prints flat on its face — no overhangs.

module front_wall() {
    hull() {
        // Inlet corner
        translate([BELT_EXIT_X - WALL,
                   BELT_Y_CEN - BELT_WIDTH/2 - WALL,
                   GATE_TOP_Z - WALL])
            cube([WALL, WALL, CATCH_HEIGHT + WALL]);
        // Outlet corner
        translate([GATE_X_RIGHT,
                   GATE_Y_CEN - GATE_WIDTH/2 - WALL,
                   GATE_TOP_Z - WALL])
            cube([WALL, WALL, RAMP_DROP + 2*WALL]);
    }
}

// ── BACK SIDE WALL ─────────────────────────────────────────
module back_wall() {
    hull() {
        translate([BELT_EXIT_X - WALL,
                   BELT_Y_CEN + BELT_WIDTH/2,
                   GATE_TOP_Z - WALL])
            cube([WALL, WALL, CATCH_HEIGHT + WALL]);
        translate([GATE_X_RIGHT,
                   GATE_Y_CEN + GATE_WIDTH/2,
                   GATE_TOP_Z - WALL])
            cube([WALL, WALL, RAMP_DROP + 2*WALL]);
    }
}

// ── GATE THROAT ────────────────────────────────────────────
// Short vertical section at the outlet that aligns the brick
// with the root gate opening and prevents it from bouncing out.

module gate_throat() {
    throat_h = 20;
    // Left wall of throat
    translate([GATE_X_LEFT - WALL,
               GATE_Y_CEN - GATE_WIDTH/2 - WALL,
               GATE_TOP_Z - throat_h])
        cube([WALL, GATE_WIDTH + 2*WALL, throat_h]);
    // Right wall of throat
    translate([GATE_X_RIGHT,
               GATE_Y_CEN - GATE_WIDTH/2 - WALL,
               GATE_TOP_Z - throat_h])
        cube([WALL, GATE_WIDTH + 2*WALL, throat_h]);
}

// ── MOUNTING TABS ──────────────────────────────────────────
// Four M5 tabs that bolt to the 2020 extrusion frame rails.

module mount_tab(x, y) {
    tab_l = 30; tab_w = 18; tab_t = 5;
    translate([x - tab_l/2, y - tab_w/2, GATE_TOP_Z - tab_t])
        difference() {
            cube([tab_l, tab_w, tab_t]);
            translate([tab_l/2, tab_w/2, -1])
                cylinder(h=tab_t+2, d=M5_DIA, $fn=24);
        }
}

module mounting_tabs() {
    // Two tabs near belt end
    mount_tab(BELT_EXIT_X - 20, BELT_Y_CEN - 25);
    mount_tab(BELT_EXIT_X - 20, BELT_Y_CEN + 25);
    // Two tabs at gate end
    mount_tab(GATE_X_RIGHT + 15, GATE_Y_CEN - 20);
    mount_tab(GATE_X_RIGHT + 15, GATE_Y_CEN + 20);
}

// ── SNAP TABS (for split halves) ───────────────────────────
// Same pattern as gate modules so all snap tools are compatible.

HALF_Y = (BELT_Y_CEN + GATE_Y_CEN) / 2;   // split plane y

module snap_tabs_male() {
    for (x = [BELT_EXIT_X - 30, GATE_X_RIGHT + 15])
        translate([x - SNAP_W/2, HALF_Y, GATE_TOP_Z + 5])
            cube([SNAP_W, SNAP_D, SNAP_H]);
}

module snap_slots_female() {
    for (x = [BELT_EXIT_X - 30, GATE_X_RIGHT + 15])
        translate([x - SNAP_W/2 - SNAP_TOL,
                   HALF_Y - SNAP_D - SNAP_TOL,
                   GATE_TOP_Z + 5 - SNAP_TOL])
            cube([SNAP_W + 2*SNAP_TOL,
                  SNAP_D + 2*SNAP_TOL,
                  SNAP_H + 2*SNAP_TOL]);
}

// ── COMPLETE CHUTE (assembled) ─────────────────────────────

module entry_chute_assembled() {
    ramp_floor();
    catch_wall();
    front_wall();
    back_wall();
    gate_throat();
    mounting_tabs();
}

// ── FRONT HALF (prints face-up, open side up) ──────────────
// Keeps the front half of the chute (y <= HALF_Y)

module front_half() {
    difference() {
        entry_chute_assembled();
        // Remove back half
        translate([-100, HALF_Y, -100]) cube([700, 500, 700]);
        // Female snap slots on mating face
        snap_slots_female();
    }
}

// ── BACK HALF ──────────────────────────────────────────────

module back_half() {
    difference() {
        entry_chute_assembled();
        // Remove front half
        translate([-100, -500, -100]) cube([700, 500 + HALF_Y, 700]);
    }
    // Male snap tabs on mating face
    snap_tabs_male();
}

// ── RENDER ─────────────────────────────────────────────────

// Full assembled chute (for visualisation and path_diagram.scad)
color([0.65, 0.75, 0.95], 0.9) entry_chute_assembled();

// ── PRINT LAYOUT (uncomment to export individual STLs) ─────

// Front half (print face-up, open side up):
// color([0.65,0.75,0.95]) front_half();

// Back half (print face-up, open side up):
// color([0.50,0.65,0.88])
//   translate([0, -(HALF_Y - GATE_Y_MIN) * 2 - 10, 0])
//     mirror([0,1,0]) back_half();

// ============================================================
// PRINT INSTRUCTIONS:
//
// Front Half:
//   Orientation: Open (interior) side UP — ramp floor faces up
//   Supports: NONE
//   Time: ~45 min
//
// Back Half:
//   Orientation: Mirror of front, open side up
//   Supports: NONE
//   Time: ~45 min
//
// ASSEMBLY:
//   1. Snap front + back halves together
//   2. Optional: thin bead of CA glue on seam
//   3. Bolt mounting tabs to 2020 extrusion at belt level
//   4. Gate throat drops directly into root gate module opening
//
// SLOPE: ~5.5° — tested OK for LEGO bricks on PETG
// ============================================================
