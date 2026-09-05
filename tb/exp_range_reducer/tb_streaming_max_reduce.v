`timescale 1ns/1ps

module tb_streaming_max_reduce;

    // ============================================================
    // TEST PARAMETER
    // Override from command line:
    //
    // iverilog -g2012 -P tb_streaming_max_reduce.N=57 ...
    //
    // ============================================================

    parameter integer N = 4;

    // ============================================================
    // DUT SIGNALS
    // ============================================================

    reg         clk;
    reg         rst;
    reg         start;

    reg  [31:0] x_in;
    reg         x_valid;

    wire [31:0] reduced_out;
    wire        reduced_valid;

    wire [31:0] max_value;

    wire        busy;
    wire        done;

    // ============================================================
    // DUT
    // ============================================================

    streaming_max_reduce #(
        .N(N)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),

        .x_in(x_in),
        .x_valid(x_valid),

        .reduced_out(reduced_out),
        .reduced_valid(reduced_valid),

        .max_value(max_value),

        .busy(busy),
        .done(done)
    );

    // ============================================================
    // CLOCK
    // ============================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // TEST DATA
    //
    // Integer values are converted to IEEE-754 FP32.
    //
    // We intentionally use values that are exactly representable
    // in FP32 so that this TB tests the RTL rather than FP rounding.
    // ============================================================

    integer input_data [0:N-1];

    integer expected_max;
    integer expected_reduced;

    integer i;
    integer errors;
    integer output_count;

    // ============================================================
    // INTEGER -> FP32
    //
    // Supports positive and negative integers.
    // ============================================================

    function [31:0] int_to_fp32;
    input integer value;

    reg        sign;
    reg [7:0]  exponent_field;
    reg [22:0] mantissa_field;

    integer abs_value;
    integer exponent;
    integer mantissa;
    integer temp;

    begin

        if (value == 0) begin

            int_to_fp32 = 32'h00000000;

        end
        else begin

            // ------------------------------------------------
            // Sign and absolute value
            // ------------------------------------------------

            if (value < 0) begin
                sign = 1'b1;
                abs_value = -value;
            end
            else begin
                sign = 1'b0;
                abs_value = value;
            end

            // ------------------------------------------------
            // Find highest set bit
            // ------------------------------------------------

            temp = abs_value;
            exponent = 0;

            while (temp > 1) begin
                temp = temp >> 1;
                exponent = exponent + 1;
            end

            // ------------------------------------------------
            // IEEE-754 exponent
            // ------------------------------------------------

            exponent_field = exponent + 127;

            // ------------------------------------------------
            // Build mantissa
            // ------------------------------------------------

            if (exponent <= 23) begin

                mantissa = abs_value << (23 - exponent);

            end
            else begin

                mantissa = abs_value >> (exponent - 23);

            end

            // Remove implicit leading 1
            mantissa_field = mantissa & 23'h7FFFFF;

            // ------------------------------------------------
            // Assemble FP32
            // ------------------------------------------------

            int_to_fp32 = {
                sign,
                exponent_field,
                mantissa_field
            };

        end

    end

endfunction

    // ============================================================
    // FP32 -> INTEGER
    //
    // Used only for our exact integer test values.
    // ============================================================

    function integer fp32_to_int;
        input [31:0] fp;

        integer exponent;
        integer fraction;
        integer result;

        begin

            // Zero
            if (fp == 32'h00000000) begin

                fp32_to_int = 0;

            end
            else begin

                exponent = fp[30:23] - 127;

                // Restore hidden leading 1
                fraction = {1'b1, fp[22:0]};

                if (exponent >= 23) begin

                    result = fraction << (exponent - 23);

                end
                else begin

                    result = fraction >> (23 - exponent);

                end

                if (fp[31])
                    result = -result;

                fp32_to_int = result;

            end

        end

    endfunction

    // ============================================================
    // GENERATE TEST VECTOR
    //
    // Produces deterministic values across the whole N range.
    //
    // Example:
    //
    // -20, -33, -16, 1, 18, 35, -49, ...
    //
    // We force the last element to 37.
    // ============================================================

    task generate_vectors;

        integer j;

        begin

            // ----------------------------------------------------
            // Generate deterministic pattern
            // ----------------------------------------------------

            for (j = 0; j < N; j = j + 1) begin

                input_data[j] =
                    ((j * 17) % 101) - 50;

            end

            // ----------------------------------------------------
            // Force first value
            // ----------------------------------------------------

            input_data[0] = -20;

            // ----------------------------------------------------
            // Force maximum
            //
            // 43 will be present in the sequence for sufficiently
            // large N. To make the test independent of N, force
            // a known maximum near the end.
            // ----------------------------------------------------

            if (N >= 2)
                input_data[N-1] = 37;

            if (N >= 3)
                input_data[N-2] = 43;

            // ----------------------------------------------------
            // Calculate expected maximum
            // ----------------------------------------------------

            expected_max = input_data[0];

            for (j = 1; j < N; j = j + 1) begin

                if (input_data[j] > expected_max)
                    expected_max = input_data[j];

            end

        end

    endtask

    // ============================================================
    // SEND VECTOR
    // ============================================================

    task send_vector;

        integer j;

        begin

            // ----------------------------------------------------
            // Start pulse
            // ----------------------------------------------------

            @(negedge clk);

            start  = 1'b1;
            x_valid = 1'b0;

            @(negedge clk);

            start = 1'b0;

            // ----------------------------------------------------
            // Send N inputs
            // ----------------------------------------------------

            for (j = 0; j < N; j = j + 1) begin

                @(negedge clk);

                x_in    = int_to_fp32(input_data[j]);
                x_valid = 1'b1;

            end

            // ----------------------------------------------------
            // Stop valid
            // ----------------------------------------------------

            @(negedge clk);

            x_valid = 1'b0;
            x_in    = 32'h00000000;

        end

    endtask

    // ============================================================
    // OUTPUT CHECKER
    //
    // IMPORTANT:
    //
    // We sample at NEGEDGE.
    //
    // DUT updates reduced_out at POSEDGE using non-blocking
    // assignments. Sampling at the following NEGEDGE guarantees
    // that the updated value is visible.
    // ============================================================

    always @(negedge clk) begin

        if (reduced_valid) begin

            // Safety check
            if (output_count >= N) begin

                $display(
                    "ERROR N=%0d: EXTRA OUTPUT index=%0d value=%0d",
                    N,
                    output_count,
                    fp32_to_int(reduced_out)
                );

                errors = errors + 1;

            end
            else begin

                expected_reduced =
                    input_data[output_count] - expected_max;

                // ------------------------------------------------
                // Check value
                // ------------------------------------------------

                if (fp32_to_int(reduced_out) !=
                    expected_reduced) begin

                    $display(
                        "ERROR N=%0d index=%0d input=%0d expected=%0d got=%0d",
                        N,
                        output_count,
                        input_data[output_count],
                        expected_reduced,
                        fp32_to_int(reduced_out)
                    );

                    errors = errors + 1;

                end
                else begin

                    $display(
                        "PASS  N=%0d index=%0d input=%0d reduced=%0d",
                        N,
                        output_count,
                        input_data[output_count],
                        fp32_to_int(reduced_out)
                    );

                end

                output_count = output_count + 1;

            end

        end

    end

    // ============================================================
    // MAIN TEST
    // ============================================================

    initial begin

        // --------------------------------------------------------
        // Initial values
        // --------------------------------------------------------

        rst       = 1'b1;
        start     = 1'b0;
        x_in      = 32'h00000000;
        x_valid   = 1'b0;

        errors      = 0;
        output_count = 0;

        // --------------------------------------------------------
        // Generate vector
        // --------------------------------------------------------

        generate_vectors();

        // --------------------------------------------------------
        // Reset
        // --------------------------------------------------------

        repeat (3)
            @(negedge clk);

        rst = 1'b0;

        // --------------------------------------------------------
        // Display test information
        // --------------------------------------------------------

        $display("");
        $display("==============================================");
        $display(" STREAMING MAX REDUCE TEST");
        $display(" N = %0d", N);
        $display(" Expected MAX = %0d", expected_max);
        $display("==============================================");
        $display("");

        // --------------------------------------------------------
        // Send vector
        // --------------------------------------------------------

        send_vector();

        // --------------------------------------------------------
        // Wait for DUT completion
        // --------------------------------------------------------

        wait(done);

        // Allow final output/checker activity
        @(negedge clk);
        @(negedge clk);

        // --------------------------------------------------------
        // Check maximum
        // --------------------------------------------------------

        if (fp32_to_int(max_value) != expected_max) begin

            $display(
                "ERROR N=%0d MAX expected=%0d got=%0d",
                N,
                expected_max,
                fp32_to_int(max_value)
            );

            errors = errors + 1;

        end
        else begin

            $display(
                "PASS  N=%0d MAX=%0d",
                N,
                expected_max
            );

        end

        // --------------------------------------------------------
        // Check number of outputs
        // --------------------------------------------------------

        if (output_count != N) begin

            $display(
                "ERROR N=%0d output count expected=%0d got=%0d",
                N,
                N,
                output_count
            );

            errors = errors + 1;

        end
        else begin

            $display(
                "PASS  N=%0d output count=%0d",
                N,
                output_count
            );

        end

        // --------------------------------------------------------
        // Final result
        // --------------------------------------------------------

        $display("");

        if (errors == 0) begin

            $display("==============================================");
            $display(" PASS: streaming_max_reduce");
            $display(" N = %0d", N);
            $display(" ALL TESTS PASSED");
            $display("==============================================");

        end
        else begin

            $display("==============================================");
            $display(" FAIL: streaming_max_reduce");
            $display(" N = %0d", N);
            $display(" ERRORS = %0d", errors);
            $display("==============================================");

        end

        $display("");

        $finish;

    end

endmodule