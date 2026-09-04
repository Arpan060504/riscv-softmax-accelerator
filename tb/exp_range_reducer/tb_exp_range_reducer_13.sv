`timescale 1ns/1ps

module tb_exp_range_reducer_13;

    localparam integer N = 13;

    logic clk;
    logic rst;
    logic start;

    logic [31:0] data_in;
    logic        valid_in;

    logic [31:0] data_out;
    logic        valid_out;

    logic        busy;
    logic        done;

    logic [31:0] max_value;

    // ============================================================
    // DUT
    // ============================================================

    exp_range_reducer #(
        .N(N)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .data_in   (data_in),
        .valid_in  (valid_in),
        .data_out  (data_out),
        .valid_out (valid_out),
        .busy      (busy),
        .done      (done),
        .max_value (max_value)
    );

    // ============================================================
    // Clock
    // ============================================================

    always #5 clk = ~clk;

    // ============================================================
    // Test vector
    //
    // Maximum = 8.0
    //
    // x:
    //  1.0
    //  3.0
    //  2.0
    //  7.0
    //  4.0
    //  5.5
    //  8.0
    //  2.5
    //  6.0
    //  0.5
    //  3.5
    //  7.5
    //  1.5
    //
    // Expected reduced:
    //
    // -7.0
    // -5.0
    // -6.0
    // -1.0
    // -4.0
    // -2.5
    //  0.0
    // -5.5
    // -2.0
    // -7.5
    // -4.5
    // -0.5
    // -6.5
    // ============================================================

    logic [31:0] test_data [0:N-1];

    initial begin

        test_data[0]  = 32'h3F800000; // 1.0
        test_data[1]  = 32'h40400000; // 3.0
        test_data[2]  = 32'h40000000; // 2.0
        test_data[3]  = 32'h40E00000; // 7.0
        test_data[4]  = 32'h40800000; // 4.0
        test_data[5]  = 32'h40B00000; // 5.5
        test_data[6]  = 32'h41000000; // 8.0
        test_data[7]  = 32'h40200000; // 2.5
        test_data[8]  = 32'h40C00000; // 6.0
        test_data[9]  = 32'h3F000000; // 0.5
        test_data[10] = 32'h40600000; // 3.5
        test_data[11] = 32'h40F00000; // 7.5
        test_data[12] = 32'h3FC00000; // 1.5

    end

    // ============================================================
    // Stimulus
    // ============================================================

    integer i;

    initial begin

        clk      = 1'b0;
        rst      = 1'b1;
        start    = 1'b0;
        valid_in = 1'b0;
        data_in  = 32'h00000000;

        // Reset
        #20;

        rst = 1'b0;

        // --------------------------------------------------------
        // Start
        // --------------------------------------------------------

        @(posedge clk);

        start = 1'b1;

        @(posedge clk);

        start = 1'b0;

        // --------------------------------------------------------
        // Send 13 inputs
        // --------------------------------------------------------

        for (i = 0; i < N; i = i + 1) begin

            @(posedge clk);

            data_in  = test_data[i];
            valid_in = 1'b1;

        end

        @(posedge clk);

        valid_in = 1'b0;
        data_in  = 32'h00000000;

        // --------------------------------------------------------
        // Wait for completion
        // --------------------------------------------------------

        wait(done);

        #20;

        $finish;

    end

    // ============================================================
    // Monitor
    // ============================================================

    always @(posedge clk) begin

        if (valid_out) begin

            $display(
                "TIME=%0t | REDUCED OUTPUT = %h",
                $time,
                data_out
            );

        end

        if (done) begin

            $display(
                "TIME=%0t | DONE | MAX = %h",
                $time,
                max_value
            );
        end

    end

endmodule