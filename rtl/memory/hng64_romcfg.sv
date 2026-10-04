// SPDX-License-Identifier: GPL-3.0-or-later
//
// The DDR3 layout, from `<rom index="1">` (docs/MEMORY.md).
//
// The image is packed per set - `scrtile` and `sprtile` differ by 32 MB between the sets in
// scope, and the tile reorder needs half the `scrtile` region at run time - so the bases and
// sizes come from the .mra rather than from a parameter here. scripts/build_mra.py emits the
// blob and the parts from one layout(), so they cannot disagree.
//
// The blob is "HNG3" then a 32-bit base and a 32-bit size, big-endian, per region, in the
// order below, then a 32-bit flags word (bit 0: init_ss64's m_samsho64_3d_hack). A size
// of zero means the .mra does not carry that region, which is how an .mra says it has no 3D data.
//
// Index 1 arrives before index 0 (the HPS sends roms in file order), so `valid` is up before
// anything reads DDR3. It is not cleared by a later download: an OSD reset re-sends nothing.

module hng64_romcfg #(
    parameter int N = 7                 // gameprg, bios, scrtile, sprtile, textures0, verts, l7a1045
) (
    input  logic        clk,

    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic  [7:0] ioctl_dout,

    output logic [27:0] base [0:N-1],
    output logic [27:0] size [0:N-1],
    output logic [31:0] flags,
    output logic        valid
);

    localparam int BYTES = 4 + 8 * N + 4;

    logic [7:0] blob [0:BYTES-1];
    logic       seen [0:BYTES-1];

    initial begin
        for (int i = 0; i < BYTES; i++) seen[i] = 1'b0;
    end

    always_ff @(posedge clk) begin
        if (ioctl_download && ioctl_index == 16'd1 && ioctl_wr && ioctl_addr < BYTES) begin
            blob[ioctl_addr[$clog2(BYTES)-1:0]] <= ioctl_dout;
            seen[ioctl_addr[$clog2(BYTES)-1:0]] <= 1'b1;
        end
    end

    // A 32-bit field is read as 28: the window is 256 MB, and build_mra.py refuses a layout
    // that does not fit it.
    function automatic [27:0] be28(input int byte0);
        be28 = {blob[byte0][3:0], blob[byte0+1], blob[byte0+2], blob[byte0+3]};
    endfunction

    always_comb begin
        logic all_seen;
        all_seen = 1'b1;
        for (int i = 0; i < BYTES; i++) all_seen = all_seen && seen[i];
        for (int r = 0; r < N; r++) begin
            base[r] = be28(4 + 8 * r);
            size[r] = be28(4 + 8 * r + 4);
        end
        flags = {blob[BYTES-4], blob[BYTES-3], blob[BYTES-2], blob[BYTES-1]};
        valid = all_seen && blob[0] == "H" && blob[1] == "N" && blob[2] == "G"
                         && blob[3] == "3";
    end

endmodule
