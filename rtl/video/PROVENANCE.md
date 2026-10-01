# Vendored video modules

The rest of `rtl/video/` is written here.

## crt_adjust.sv

- Author: Umberto Parisi (rmonic79), GPL-3.0-or-later
- Upstream: https://github.com/rmonic79/Arcade-Raiden_MiSTer, `rtl/Raiden/crt_adjust.sv`
- Copied from: `Arcade-Seta_MiSTer/rtl/video/crt_adjust.sv`, which already carries a signedness fix
  to H-Position (its header)
- Changed here, as its header states: the line buffer's address width is the parameter `LB_AW`
  (a 768-pixel line needs 11 bits), and V-Shift's tap is 10 bits (528 lines)
- Used by: `hng64_crt.sv`
