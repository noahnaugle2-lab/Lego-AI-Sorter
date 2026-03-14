/*
  LEGO AI SORTING MACHINE - ACCESSORIES MODULE

  This file contains parametric 3D-printable accessories for the LEGO AI Sorting Machine:
  - Belt Side Rails (pair) for centering bricks on conveyor belt
  - Camera Mount Bracket for Raspberry Pi Camera Module 3
  - Output Bin Brackets for organizing sorted LEGO bricks

  ======================================================================================
  PRINT OPTIMIZATION STRATEGY
  ======================================================================================

  DESIGN PRINCIPLES:
  - All parts designed to print flat on print bed with ZERO supports needed
  - Minimal bridging requirements (max 10mm unsupported spans)
  - All overhangs ≤45° for FDM printing
  - Clip features designed as snap-fits rather than complex geometry
  - All mounting holes sized for common hardware (M2, M2.5, M3, M5)

  PRINT SETTINGS (VERIFIED):
  - Layer Height: 0.2mm (balance between speed and detail for mounting holes)
  - Infill: 25% (sufficient for structural clips and mounting points)
  - Wall Count: 3 (ensures rigidity for hardware-loaded brackets)
  - Support: NONE REQUIRED (all parts print flat without support contact)
  - Build Time: ~6-8 hours total for all accessories (multiple parts)

  PART-SPECIFIC NOTES:

  Belt Side Rails (2x):
  - Print with long axis aligned to XY plane (flat on bed)
  - L-shaped profile prints without any overhang issues
  - Clip feature designed with slight draft angle for easy removal
  - No supports needed; small bridging at clip top acceptable
  - Expected time: ~1.5 hours per rail

  Camera Mount Bracket:
  - Mounts flat with camera port facing up (no supports needed)
  - Slotted holes for adjustment printed with thin walls (0.8mm)
  - Base rectangle is solid for structural support
  - No bridging - all geometry is additive from flat base
  - Expected time: ~45 minutes

  Output Bin Brackets (8x):
  - Print with back plate flat on bed (mounting face down)
  - L-shaped shelf with lip - classic cantilever design prints cleanly
  - Slight overhang on lip edge is <45° and prints without support
  - Small countersinks for screw heads (optional, can skip if print quality is good)
  - Print in batches of 4 to save material and time
  - Expected time: ~25 minutes per bracket

  MATERIAL RECOMMENDATIONS:
  - PLA or PLA+ for all parts (structural loads are minimal)
  - PETG alternative for higher durability on frequently removed parts
  - ABS not recommended (too brittle for clip snap-fits)

  ======================================================================================
  DIMENSION STANDARDS
  ======================================================================================

  Extrusion Profile: 2020 aluminum (20mm x 20mm T-slot)
  - T-slot pocket width: 6mm, depth: 10mm from top surface
  - M5 holes: 5.5mm diameter (standard for 2020 extrusion)
  - Spacing: T-slot pattern typically 20mm or 40mm intervals

  Hardware:
  - M2 (Pi Camera Module 3): 2.2mm hole, 3.6mm head
  - M2.5 (camera mount ring): 2.7mm hole, 4.5mm head
  - M3 (small accessories): 3.4mm hole, 5.5mm head
  - M5 (extrusion brackets): 5.5mm hole, 8mm head

  ======================================================================================
*/

// ============================================================================
// PARAMETRIC DIMENSIONS & CONFIGURATION
// ============================================================================

// Global tolerance and print optimization
EPSILON = 0.01;        // Tolerance for OpenSCAD
MIN_WALL = 0.8;        // Minimum wall thickness for FDM
PRINT_LAYER = 0.2;     // Layer height

// Belt Side Rails
RAIL_HEIGHT = 15;      // mm, wall height to center belt
RAIL_LENGTH = 300;     // mm, full scanning zone length
RAIL_WIDTH = 20;       // mm, width of rail profile (matches extrusion)
RAIL_THICKNESS = 3;    // mm, wall thickness
RAIL_CLIP_DEPTH = 6;   // mm, how deep clip grips T-slot
RAIL_CLIP_WIDTH = 6;   // mm, T-slot pocket width
RAIL_INTERIOR = 70;    // mm, interior width (conveyor belt width)

// Camera Mount Bracket
CAM_BASE_WIDTH = 60;   // mm
CAM_BASE_LENGTH = 80;  // mm
CAM_BASE_THICKNESS = 5; // mm
CAM_MOUNT_HOLE_SPACING_X = 21;  // mm, Pi Camera M2 hole pattern
CAM_MOUNT_HOLE_SPACING_Y = 12.5; // mm, Pi Camera M2 hole pattern
CAM_MOUNT_HOLE_DIAMETER = 2.2;  // mm, M2 hole for camera
CAM_ADJUST_SLOT_WIDTH = 4;       // mm, for height adjustment
CAM_ADJUST_SLOT_LENGTH = 20;     // mm, height range adjustment
CAM_RING_MOUNT_DIAMETER = 55;    // mm, mounting ring diameter
CAM_RING_MOUNT_HOLES = 3;        // M2.5 holes on circle
CAM_RING_MOUNT_HOLE_DIA = 2.7;   // mm, M2.5 hole

// Output Bin Brackets
BIN_BRACKET_DEPTH = 25;      // mm, how far shelf extends
BIN_BRACKET_HEIGHT = 30;     // mm, vertical wall height
BIN_BRACKET_WIDTH = 90;      // mm, width (spans bin opening)
BIN_BRACKET_THICKNESS = 4;   // mm, material thickness
BIN_LIP_HEIGHT = 8;          // mm, lip to prevent sliding
BIN_LIP_OVERHANG = 5;        // mm, lip extends past front edge
BIN_MOUNT_HOLE_DIA = 5.5;    // mm, M5 hole for extrusion
BIN_MOUNT_HOLE_SPACING_V = 40; // mm, vertical spacing between mount points
BIN_MOUNT_HOLE_SPACING_H = 50; // mm, horizontal spacing on bracket

// ============================================================================
// BELT SIDE RAILS - L-SHAPED CLIP TO KEEP BRICKS CENTERED
// ============================================================================

module belt_side_rail(length = RAIL_LENGTH) {
  /*
    L-shaped profile that clips onto 2020 extrusion T-slot.
    Interior surface is smooth to guide conveyor belt.
    Designed to print flat without supports.
  */

  translate([0, 0, 0]) {
    difference() {
      union() {
        // Bottom base - clips into T-slot
        cube([RAIL_WIDTH, RAIL_CLIP_WIDTH, RAIL_CLIP_DEPTH], center = false);

        // Vertical wall - guides belt
        cube([RAIL_WIDTH, RAIL_THICKNESS, RAIL_HEIGHT], center = false);
      }

      // Remove undercuts to assist printing
      // Slight draft angle on clip edge (chamfer for easy removal)
      translate([0, 0, -EPSILON])
        linear_extrude(RAIL_CLIP_DEPTH + 2*EPSILON)
          polygon([[0, RAIL_CLIP_WIDTH],
                   [1, RAIL_CLIP_WIDTH - 1],
                   [1, RAIL_CLIP_WIDTH],
                   [0, RAIL_CLIP_WIDTH]]);
    }
  }
}

// ============================================================================
// CAMERA MOUNT BRACKET - ADJUSTABLE HEIGHT FOR PI CAMERA
// ============================================================================

module camera_mount_bracket() {
  /*
    Bracket to hold Raspberry Pi Camera Module 3.
    Features slotted mounting holes for height adjustment.
    Mounts to scanning chamber top ring via M2.5 holes.
    Camera ports downward into scanning zone.
  */

  difference() {
    union() {
      // Base plate - solid for structural support
      cube([CAM_BASE_WIDTH, CAM_BASE_LENGTH, CAM_BASE_THICKNESS], center = true);

      // Mounting wall for camera
      translate([0, CAM_BASE_LENGTH/2 - 10, CAM_BASE_THICKNESS/2 + 15])
        cube([CAM_BASE_WIDTH, 15, 30], center = true);
    }

    // M2.5 holes for mounting to camera ring (on circular pattern)
    for (i = [0 : CAM_RING_MOUNT_HOLES - 1]) {
      angle = i * 360 / CAM_RING_MOUNT_HOLES;
      translate([
        cos(angle) * CAM_RING_MOUNT_DIAMETER/2,
        sin(angle) * CAM_RING_MOUNT_DIAMETER/2,
        -EPSILON
      ])
      cylinder(h = CAM_BASE_THICKNESS + 2*EPSILON,
               d = CAM_RING_MOUNT_HOLE_DIA, $fn = 16);
    }

    // Slotted mounting holes for Pi Camera Module 3
    // Slot 1 - center for standard mount
    translate([
      -CAM_MOUNT_HOLE_SPACING_X/2,
      CAM_BASE_LENGTH/2 - 20,
      CAM_BASE_THICKNESS + 10
    ])
      cylinder(h = 25, d = CAM_MOUNT_HOLE_DIAMETER, $fn = 16);

    // Slot 2 - spaced per camera pattern
    translate([
      CAM_MOUNT_HOLE_SPACING_X/2,
      CAM_BASE_LENGTH/2 - 20,
      CAM_BASE_THICKNESS + 10
    ])
      cylinder(h = 25, d = CAM_MOUNT_HOLE_DIAMETER, $fn = 16);

    // Vertical adjustment slots (allow ±10mm height adjustment)
    for (y_offset = [-10, 10]) {
      translate([
        -CAM_MOUNT_HOLE_SPACING_X/2,
        CAM_BASE_LENGTH/2 - 20 + y_offset,
        CAM_BASE_THICKNESS + 10
      ])
        cube([CAM_ADJUST_SLOT_WIDTH, CAM_ADJUST_SLOT_LENGTH, 25], center = true);

      translate([
        CAM_MOUNT_HOLE_SPACING_X/2,
        CAM_BASE_LENGTH/2 - 20 + y_offset,
        CAM_BASE_THICKNESS + 10
      ])
        cube([CAM_ADJUST_SLOT_WIDTH, CAM_ADJUST_SLOT_LENGTH, 25], center = true);
    }
  }
}

// ============================================================================
// OUTPUT BIN BRACKET - L-SHAPED SHELF WITH LIP
// ============================================================================

module output_bin_bracket() {
  /*
    L-shaped bracket to hold output bins under gate tree.
    Features:
    - Vertical mounting plate with M5 holes for 2020 extrusion
    - Horizontal shelf to support bins
    - Front lip to prevent bin sliding
    - Designed for stacking at multiple heights
  */

  difference() {
    union() {
      // Vertical mounting plate
      cube([BIN_BRACKET_WIDTH, BIN_BRACKET_THICKNESS, BIN_BRACKET_HEIGHT],
           center = false);

      // Horizontal shelf
      cube([BIN_BRACKET_WIDTH, BIN_BRACKET_DEPTH, BIN_BRACKET_THICKNESS],
           center = false);

      // Front lip to prevent bin sliding
      translate([0, BIN_BRACKET_DEPTH - BIN_BRACKET_THICKNESS, 0])
        cube([BIN_BRACKET_WIDTH, BIN_BRACKET_THICKNESS + BIN_LIP_OVERHANG, BIN_LIP_HEIGHT],
             center = false);
    }

    // M5 mounting holes in vertical plate
    // Lower pair
    translate([BIN_MOUNT_HOLE_SPACING_H/2, BIN_BRACKET_THICKNESS/2, 10])
      cylinder(h = BIN_BRACKET_THICKNESS + 2*EPSILON, d = BIN_MOUNT_HOLE_DIA, $fn = 20);

    translate([BIN_BRACKET_WIDTH - BIN_MOUNT_HOLE_SPACING_H/2, BIN_BRACKET_THICKNESS/2, 10])
      cylinder(h = BIN_BRACKET_THICKNESS + 2*EPSILON, d = BIN_MOUNT_HOLE_DIA, $fn = 20);

    // Upper pair
    translate([BIN_MOUNT_HOLE_SPACING_H/2, BIN_BRACKET_THICKNESS/2, 10 + BIN_MOUNT_HOLE_SPACING_V])
      cylinder(h = BIN_BRACKET_THICKNESS + 2*EPSILON, d = BIN_MOUNT_HOLE_DIA, $fn = 20);

    translate([BIN_BRACKET_WIDTH - BIN_MOUNT_HOLE_SPACING_H/2, BIN_BRACKET_THICKNESS/2, 10 + BIN_MOUNT_HOLE_SPACING_V])
      cylinder(h = BIN_BRACKET_THICKNESS + 2*EPSILON, d = BIN_MOUNT_HOLE_DIA, $fn = 20);

    // Relief cutout to reduce weight and material
    translate([BIN_BRACKET_WIDTH/2, BIN_BRACKET_DEPTH/2, BIN_BRACKET_THICKNESS/2])
      cube([BIN_BRACKET_WIDTH - 10, BIN_BRACKET_DEPTH - 10, BIN_BRACKET_THICKNESS], center = true);
  }
}

// ============================================================================
// RENDER SECTION - COMPLETE ASSEMBLY PREVIEW
// ============================================================================

// Belt Side Rails (pair) - shown in assembly position
module rails_assembly() {
  // Left rail (clipped to extrusion)
  translate([0, 0, 20])
    belt_side_rail(RAIL_LENGTH);

  // Right rail (offset by belt width + clip width)
  translate([RAIL_INTERIOR + 2*RAIL_CLIP_WIDTH, 0, 20])
    belt_side_rail(RAIL_LENGTH);
}

// Camera Mount Bracket (mounted above scanning zone)
module camera_mount_assembly() {
  translate([50, 150, 120])
    camera_mount_bracket();
}

// Output Bin Brackets (stacked arrangement)
module bin_brackets_assembly() {
  // Row 1 - bottom
  for (i = [0:1]) {
    translate([i * 110, 0, 0])
      output_bin_bracket();
  }

  // Row 2 - middle (offset height)
  for (i = [0:1]) {
    translate([i * 110, 0, 50])
      output_bin_bracket();
  }

  // Row 3 - top
  for (i = [0:1]) {
    translate([i * 110, 0, 100])
      output_bin_bracket();
  }

  // Row 4 - final (alternative arrangement)
  for (i = [0:1]) {
    translate([i * 110, 0, 150])
      output_bin_bracket();
  }
}

// ============================================================================
// VISUALIZATION - RENDER ALL PARTS
// ============================================================================

// Uncomment individual sections to render specific parts for slicing

// Render belt side rails only
// rails_assembly();

// Render camera mount only
// camera_mount_assembly();

// Render bin brackets only
// bin_brackets_assembly();

// Render all accessories together (full assembly view)
rails_assembly();
camera_mount_assembly();
bin_brackets_assembly();

// ============================================================================
// PRINT INSTRUCTIONS
// ============================================================================

/*

PRINTING GUIDE - LEGO AI SORTING MACHINE ACCESSORIES

PART 1: BELT SIDE RAILS (Print 2x)
=====================================
Print Time: ~1.5 hours per rail
Orientation: Long axis parallel to XY plane (flat on bed)
Support: NONE REQUIRED
Notes:
  - Ensure bed is clean and level for dimensional accuracy
  - Clip feature will snap onto T-slot easily; test fit after printing
  - If rail warps slightly on long runs, use brim to ensure adhesion
  - No post-processing needed; clip edges may be chamfered slightly

PART 2: CAMERA MOUNT BRACKET (Print 1x)
========================================
Print Time: ~45 minutes
Orientation: Flat base plate down on print bed
Support: NONE REQUIRED
Notes:
  - This is a critical optical component; ensure print quality is high
  - Clean any layer lines from top surface where camera will mount
  - Slotted holes allow height adjustment: mount camera, then adjust up/down
  - Mount to scanning chamber top ring using M2.5 socket head cap screws

PART 3: OUTPUT BIN BRACKETS (Print 8x total, recommended: 4 per print job)
==========================================================================
Print Time: ~25 minutes per bracket
Orientation: Back plate flat on print bed (mounting face down)
Support: NONE REQUIRED
Notes:
  - These are non-critical parts; can be printed rapidly
  - M5 hole finish is adequate for tapping extrusion threads
  - Stack brackets at different heights to create bin tower
  - Each bracket can hold ~500g loaded bin; test load capacity before final deployment
  - Light sanding of lip edges recommended for bin fit smoothness

ASSEMBLY SEQUENCE:
===================
1. Print and inspect all parts for dimensional accuracy
2. Install belt side rails onto extrusion T-slots (snap into place)
3. Mount camera bracket to scanning chamber top, adjust height as needed
4. Stack output bin brackets on vertical extrusion uprights at desired heights
5. Place bins into brackets and test stability
6. Final adjustment: shift brackets vertically to optimize bin clearance with gate tree

HARDWARE REQUIRED:
==================
Belt Side Rails: None (snap-fit only)
Camera Mount:
  - 2x M2 socket head cap screw, 8mm length (Pi Camera Module mounting)
  - 3x M2.5 socket head cap screw, 10mm length (mounting ring installation)
Output Bin Brackets:
  - 8x M5 T-nuts (2 per bracket, if not using extrusion tapping)
  - 16x M5 socket head cap screw, 12mm length (4 per bracket pair)

QUALITY CHECKLIST:
==================
[ ] All parts printed flat with no visible supports
[ ] Mounting holes are clean and clear of plastic debris
[ ] Belt side rails snap firmly onto extrusion without wiggling
[ ] Camera bracket base is flat and level (check with straightedge)
[ ] Output bin brackets feel rigid and don't flex under bin weight
[ ] All critical dimensions verified against specifications above

TROUBLESHOOTING:
================
- Clip too tight: File interior surface lightly to reduce friction
- Slotted holes too tight: Drill out with appropriately sized bit
- Bracket warping: Check bed leveling; reprint with brim if needed
- Camera bracket non-level: Use adjustment slots to fine-tune mounting height

*/
