// SPDX-License-Identifier: GPL-3.0-or-later
//
// hng64_mosaic against x - x % (m + 1) for every 11-bit x and every m from 1 to 15, and its
// latency.

`timescale 1ns/1ps

module tb_mosaic;
    logic        clk = 0;
    always #4 clk = ~clk;

    logic        start = 0;
    logic [10:0] x = 0;
    logic  [3:0] m = 0;
    logic        done;
    logic [10:0] base;

    hng64_mosaic #(.W(11)) dut (.clk(clk), .start(start), .x(x), .m(m), .done(done), .base(base));

    int bad = 0, n = 0, lat, lat_max = 0;
    initial begin
        for (int mm = 1; mm < 16; mm++) begin
            for (int xx = 0; xx < 2048; xx++) begin
                @(negedge clk);
                x = 11'(xx); m = 4'(mm); start = 1;
                @(negedge clk);
                start = 0;
                lat = 1;
                while (!done) begin @(negedge clk); lat++; end
                if (lat > lat_max) lat_max = lat;
                n++;
                if (base != 11'(xx - xx % (mm + 1))) begin
                    if (bad < 5) $display("x %0d m %0d: got %0d, want %0d", xx, mm, base, xx - xx % (mm + 1));
                    bad++;
                end
            end
        end
        $display("mosaic: %0d of %0d wrong, done %0d clocks after start: %s", bad, n, lat_max,
                 bad ? "FAIL" : "PASS");
        $finish;
    end
endmodule
