`timescale 1ns/1ps

module tb_softmax_base2;

    // ============================================================
    // PARAMETERS
    // ============================================================

    parameter integer N = 4;

    localparam integer NUM_TESTS = 8;

    // Tolerance in raw FP32 integer representation is NOT used
    // directly. We compare converted real values.
    real TOLERANCE;
    initial TOLERANCE = 0.05;


    // ============================================================
    // CLOCK / RESET
    // ============================================================

    reg clk;
    reg rst;
    reg start;

    reg [31:0] x_in;
    reg        x_valid;

    wire [31:0] softmax_out;
    wire        softmax_valid;
    wire        done;


    // ============================================================
    // DUT
    // ============================================================

    softmax_base2 #(
        .N(N)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .start        (start),

        .x_in         (x_in),
        .x_valid      (x_valid),

        .softmax_out  (softmax_out),
        .softmax_valid(softmax_valid),

        .done         (done)
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
    // Each vector contains N FP32 values.
    // ============================================================

    reg [31:0] test_vectors [0:NUM_TESTS-1][0:N-1];


    // ============================================================
    // EXPECTED / ACTUAL RESULTS
    // ============================================================

    real expected [0:N-1];
    real actual   [0:N-1];

    real sum_expected;
    real sum_actual;

    real max_value;
    real exp_value;

    integer test_number;
    integer i;
    integer j;

    integer output_count;

    integer pass_count;
    integer fail_count;


    // ============================================================
    // FP32 -> REAL
    //
    // Used only inside the simulation testbench.
    // ============================================================

    function real fp32_to_real(input [31:0] f);

        reg        sign;
        reg [7:0]  exponent;
        reg [22:0] fraction;

        real mantissa;
        integer exponent_value;

        begin

            sign     = f[31];
            exponent = f[30:23];
            fraction = f[22:0];

            // Zero
            if (exponent == 0 && fraction == 0) begin

                fp32_to_real = 0.0;

            end

            // Normalized number
            else begin

                mantissa = 1.0 + (fraction / 8388608.0);

                exponent_value = exponent - 127;

                fp32_to_real =
                    mantissa * (2.0 ** exponent_value);

                if (sign)
                    fp32_to_real = -fp32_to_real;

            end

        end

    endfunction


    // ============================================================
    // REAL -> FP32
    //
    // This is not required for expected Softmax calculation.
    // Included only for completeness.
    // ============================================================

    function [31:0] real_to_fp32(input real value);

        real abs_value;
        integer exponent_value;
        real normalized;

        reg sign;
        reg [7:0] exponent_bits;
        reg [22:0] fraction_bits;

        begin

            if (value == 0.0) begin

                real_to_fp32 = 32'h00000000;

            end

            else begin

                sign = 1'b0;

                abs_value = value;

                if (value < 0.0) begin
                    sign = 1'b1;
                    abs_value = -value;
                end

                exponent_value = 0;
                normalized = abs_value;

                while (normalized >= 2.0) begin
                    normalized = normalized / 2.0;
                    exponent_value = exponent_value + 1;
                end

                while (normalized < 1.0) begin
                    normalized = normalized * 2.0;
                    exponent_value = exponent_value - 1;
                end

                exponent_bits = exponent_value + 127;

                fraction_bits =
                    (normalized - 1.0) * 8388608.0;

                real_to_fp32 = {
                    sign,
                    exponent_bits,
                    fraction_bits
                };

            end

        end

    endfunction


    // ============================================================
    // CALCULATE EXPECTED SOFTMAX
    //
    // softmax(i) =
    //
    // exp(xi - max(x))
    // -----------------
    // sum(exp(xj-max))
    //
    // This is floating-point reference calculation performed
    // by the simulator.
    // ============================================================

    task calculate_expected;

        real x_real;
        real shifted;
        real exp_temp;

        begin

            // ----------------------------------------------------
            // Find maximum
            // ----------------------------------------------------

            max_value = fp32_to_real(test_vectors[test_number][0]);

            for (i = 1; i < N; i = i + 1) begin

                x_real =
                    fp32_to_real(test_vectors[test_number][i]);

                if (x_real > max_value)
                    max_value = x_real;

            end


            // ----------------------------------------------------
            // Calculate exponentials
            // ----------------------------------------------------

            sum_expected = 0.0;

            for (i = 0; i < N; i = i + 1) begin

                x_real =
                    fp32_to_real(test_vectors[test_number][i]);

                shifted = x_real - max_value;

                exp_temp = $ln(2.718281828459045) ;

                // Verilog does not provide a universal exp()
                // function across simulators.
                //
                // Therefore use:
                //
                // e^x = 2^(x / ln(2))
                //
                expected[i] =
                    2.718281828459045 ** shifted;

                sum_expected =
                    sum_expected + expected[i];

            end


            // ----------------------------------------------------
            // Normalize
            // ----------------------------------------------------

            for (i = 0; i < N; i = i + 1) begin

                expected[i] =
                    expected[i] / sum_expected;

            end

        end

    endtask


    // ============================================================
    // SEND ONE INPUT VECTOR
    // ============================================================

    task send_vector;

        begin

            // ----------------------------------------------------
            // Start
            // ----------------------------------------------------

            @(posedge clk);

            start <= 1'b1;
            x_valid <= 1'b0;

            @(posedge clk);

            start <= 1'b0;


            // ----------------------------------------------------
            // Send N values
            // ----------------------------------------------------

            for (j = 0; j < N; j = j + 1) begin

                @(posedge clk);

                x_in    <= test_vectors[test_number][j];
                x_valid <= 1'b1;

            end

            @(posedge clk);

            x_valid <= 1'b0;
            x_in    <= 32'h00000000;

        end

    endtask


    // ============================================================
    // WAIT FOR OUTPUTS
    // ============================================================

    task receive_outputs;

        integer timeout;
        real error;

        begin

            output_count = 0;
            timeout = 0;

            // ----------------------------------------------------
            // Wait for first output
            // ----------------------------------------------------

            while ((output_count < N) && (timeout < 1000)) begin

                @(posedge clk);

                timeout = timeout + 1;

                if (softmax_valid) begin

                    actual[output_count] =
                        fp32_to_real(softmax_out);

                    $display(
                        "  OUTPUT[%0d] = %f",
                        output_count,
                        actual[output_count]
                    );

                    output_count =
                        output_count + 1;

                end

            end


            // ----------------------------------------------------
            // Check number of outputs
            // ----------------------------------------------------

            if (output_count != N) begin

                $display(
                    "  ERROR: Expected %0d outputs, received %0d",
                    N,
                    output_count
                );

                fail_count = fail_count + 1;

                return;

            end


            // ----------------------------------------------------
            // Compare outputs
            // ----------------------------------------------------

            sum_actual = 0.0;

            for (i = 0; i < N; i = i + 1) begin

                error =
                    actual[i] - expected[i];

                if (error < 0.0)
                    error = -error;

                sum_actual =
                    sum_actual + actual[i];

                if (error > TOLERANCE) begin

                    $display(
                        "  FAIL[%0d] expected=%f actual=%f error=%f",
                        i,
                        expected[i],
                        actual[i],
                        error
                    );

                    fail_count =
                        fail_count + 1;

                end

                else begin

                    $display(
                        "  PASS[%0d] expected=%f actual=%f error=%f",
                        i,
                        expected[i],
                        actual[i],
                        error
                    );

                end

            end


            // ----------------------------------------------------
            // Check sum of Softmax
            // ----------------------------------------------------

            error = sum_actual - 1.0;

            if (error < 0.0)
                error = -error;


            $display(
                "  SUM(actual) = %f",
                sum_actual
            );


            if (error > TOLERANCE) begin

                $display(
                    "  FAIL: Softmax sum is not approximately 1.0"
                );

                fail_count = fail_count + 1;

            end

            else begin

                $display(
                    "  PASS: Softmax sum approximately 1.0"
                );

            end


            // ----------------------------------------------------
            // Check done
            // ----------------------------------------------------

            timeout = 0;

            while (!done && timeout < 100) begin

                @(posedge clk);

                timeout = timeout + 1;

            end

            if (!done) begin

                $display(
                    "  FAIL: DONE was not asserted"
                );

                fail_count = fail_count + 1;

            end

            else begin

                $display(
                    "  PASS: DONE asserted"
                );

                pass_count = pass_count + 1;

            end

        end

    endtask


    // ============================================================
    // INITIALIZE TEST VECTORS
    // ============================================================

    initial begin

        // ========================================================
        // TEST 0
        // ========================================================

        test_vectors[0][0] = 32'h3FC00000; // 1.5
        test_vectors[0][1] = 32'h40400000; // 3.0
        test_vectors[0][2] = 32'h40000000; // 2.0
        test_vectors[0][3] = 32'h40A00000; // 5.0


        // ========================================================
        // TEST 1
        // ========================================================

        test_vectors[1][0] = 32'h3F800000; // 1.0
        test_vectors[1][1] = 32'hBF800000; // -1.0
        test_vectors[1][2] = 32'h40000000; // 2.0
        test_vectors[1][3] = 32'hC0000000; // -2.0


        // ========================================================
        // TEST 2
        // ========================================================

        test_vectors[2][0] = 32'h00000000; // 0
        test_vectors[2][1] = 32'hBF800000; // -1
        test_vectors[2][2] = 32'hC0000000; // -2
        test_vectors[2][3] = 32'hC0800000; // -4


        // ========================================================
        // TEST 3
        // Equal inputs
        //
        // Expected:
        //
        // [0.25, 0.25, 0.25, 0.25]
        // ========================================================

        test_vectors[3][0] = 32'h3F800000;
        test_vectors[3][1] = 32'h3F800000;
        test_vectors[3][2] = 32'h3F800000;
        test_vectors[3][3] = 32'h3F800000;


        // ========================================================
        // TEST 4
        // ========================================================

        test_vectors[4][0] = 32'h40A00000; // 5
        test_vectors[4][1] = 32'h40800000; // 4
        test_vectors[4][2] = 32'h40000000; // 2
        test_vectors[4][3] = 32'h3F000000; // 0.5


        // ========================================================
        // TEST 5
        // Negative values
        // ========================================================

        test_vectors[5][0] = 32'hBF800000; // -1
        test_vectors[5][1] = 32'hC0A00000; // -5
        test_vectors[5][2] = 32'hC02CCCCD; // -2.7
        test_vectors[5][3] = 32'hC1000000; // -8


        // ========================================================
        // TEST 6
        // Large separation
        // ========================================================

        test_vectors[6][0] = 32'h40A00000; // 5
        test_vectors[6][1] = 32'h3F800000; // 1
        test_vectors[6][2] = 32'hBF800000; // -1
        test_vectors[6][3] = 32'hC1200000; // -10


        // ========================================================
        // TEST 7
        // Another mixed vector
        // ========================================================

        test_vectors[7][0] = 32'h3FC00000; // 1.5
        test_vectors[7][1] = 32'h40200000; // 2.5
        test_vectors[7][2] = 32'h3F000000; // 0.5
        test_vectors[7][3] = 32'hBF000000; // -0.5

    end


    // ============================================================
    // MAIN TEST
    // ============================================================

    initial begin

        pass_count = 0;
        fail_count = 0;

        rst     = 1'b1;
        start   = 1'b0;
        x_in    = 32'h00000000;
        x_valid = 1'b0;

        // --------------------------------------------------------
        // Reset
        // --------------------------------------------------------

        repeat (5)
            @(posedge clk);

        rst = 1'b0;

        repeat (2)
            @(posedge clk);


        $display("");
        $display("==============================================");
        $display(" SOFTMAX BASE2 STREAMING TEST");
        $display(" N = %0d", N);
        $display(" NUMBER OF TESTS = %0d", NUM_TESTS);
        $display("==============================================");
        $display("");


        // ========================================================
        // RUN ALL TESTS
        // ========================================================

        for (test_number = 0;
             test_number < NUM_TESTS;
             test_number = test_number + 1) begin

            $display("");
            $display("----------------------------------------------");
            $display(" TEST %0d", test_number);
            $display("----------------------------------------------");

            // Calculate software reference
            calculate_expected;

            $display(
                "Maximum input = %f",
                max_value
            );

            $display("Expected Softmax:");

            for (i = 0; i < N; i = i + 1) begin

                $display(
                    "  expected[%0d] = %f",
                    i,
                    expected[i]
                );

            end


            // Send vector
            send_vector;

            // Receive outputs
            receive_outputs;

            // Gap between tests
            repeat (5)
                @(posedge clk);

        end


        // ========================================================
        // FINAL RESULT
        // ========================================================

        $display("");
        $display("==============================================");
        $display(" FINAL TEST RESULT");
        $display("==============================================");

        $display(
            "PASS COUNT = %0d",
            pass_count
        );

        $display(
            "FAIL COUNT = %0d",
            fail_count
        );


        if (fail_count == 0) begin

            $display("");
            $display("==============================================");
            $display(" ALL SOFTMAX TESTS PASSED");
            $display("==============================================");

        end

        else begin

            $display("");
            $display("==============================================");
            $display(" SOME SOFTMAX TESTS FAILED");
            $display("==============================================");

        end


        #100;

        $finish;

    end

endmodule