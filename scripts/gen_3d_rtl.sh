#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Regenerate the 3D rasteriser's Verilog from its SpinalHDL sources. RUN FROM THE REPOSITORY ROOT.
#
#     scripts/gen_3d_rtl.sh
#
# Writes rtl/3d/hng64_raster.v, which is committed so that neither the Quartus build nor the
# Verilator benches need Scala. Needs scala-cli and a JDK.
set -euo pipefail
[ -d sys ] || { echo "run me from the repository root"; exit 1; }
scala-cli run --server=false rtl/3d/spinal --main-class hng64.raster.GenRaster -- rtl/3d
python scripts/geo_ucode.py --export rtl/3d/spinal/geo
scala-cli run --server=false rtl/3d/spinal --main-class hng64.raster.GenGeo -- rtl/3d rtl/3d/spinal/geo
