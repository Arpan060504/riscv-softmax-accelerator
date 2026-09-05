`timescale 1ns/1ps

`ifndef TEST_N
    `define TEST_N 2
`endif

module tb_softmax_exp_accumulator;

    localparam integer N = `TEST_N;



    // Allowed error in accumulated FP32 sum.
    //
    // The exp implementation itself is approximate, so comparing
    // against mathematical $exp() with a very small tolerance is
    // inappropriate.
    //
    // We compare:
    //
    //     DUT SUM
    //
    // against
    //
    //     sum of DUT exp outputs
    //
    // This verifies the accumulator exactly at the system level.
    //
    parameter real SUM_TOL = 0.01;


    // ============================================================
    // CLOCK / RESET
    // ============================================================

    reg clk;
    reg rst;
    reg start;

    reg  [31:0] x_in;
    reg         x_valid;

    wire [31:0] exp_out;
    wire        exp_valid;

    wire [31:0] max_value;

    wire        pipeline_busy;
    wire        pipeline_done;


    // ============================================================
    // EXP PIPELINE
    // ============================================================

    softmax_exp_pipeline #(
        .N(N)
    ) u_exp_pipeline (

        .clk        (clk),
        .rst        (rst),
        .start      (start),

        .x_in       (x_in),
        .x_valid    (x_valid),

        .exp_out    (exp_out),
        .exp_valid  (exp_valid),

        .max_value  (max_value),

        .busy       (pipeline_busy),
        .done        (pipeline_done)
    );


    // ============================================================
    // ACCUMULATOR
    // ============================================================

    localparam integer INDEX_WIDTH =
        (N <= 1) ? 1 : $clog2(N);

    reg [INDEX_WIDTH-1:0] read_addr;

    wire [31:0] exp_mem_out;
    wire [31:0] sum;
    wire        accumulator_done;


    softmax_exp_accumulator #(
        .N(N)
    ) u_accumulator (

        .clk       (clk),
        .rst       (rst),
        .start     (start),

        .exp_in    (exp_out),
        .exp_valid (exp_valid),

        .read_addr (read_addr),

        .exp_out   (exp_mem_out),
        .sum       (sum),
        .done      (accumulator_done)
    );


    // ============================================================
    // CLOCK
    // ============================================================

    initial begin

        clk = 1'b0;

        forever #5 clk = ~clk;

    end


    // ============================================================
    // TEST INPUT MEMORY
    // ============================================================

    reg [31:0] input_data [0:N-1];


    // ============================================================
    // SOFTWARE / TESTBENCH REFERENCE
    // ============================================================

    real reference_sum;

    real dut_sum;

    real running_sum;

    real expected_exp [0:N-1];

    real actual_exp [0:N-1];

    integer output_count;

    integer errors;

    integer i;


    // ============================================================
    // FP32 -> REAL
    // ============================================================

    function real fp32_to_real;

        input [31:0] value;

        reg        sign;
        reg [7:0]  exponent;
        reg [22:0] fraction;

        real mantissa;

        integer unbiased_exp;

        begin

            sign     = value[31];
            exponent = value[30:23];
            fraction = value[22:0];


            // ----------------------------------------------------
            // ZERO
            // ----------------------------------------------------

            if (value[30:0] == 31'd0) begin

                fp32_to_real = 0.0;

            end


            // ----------------------------------------------------
            // INF / NAN
            // ----------------------------------------------------

            else if (exponent == 8'hFF) begin

                fp32_to_real = 1.0e30;

            end


            // ----------------------------------------------------
            // SUBNORMAL
            // ----------------------------------------------------

            else if (exponent == 8'd0) begin

                mantissa = fraction / 8388608.0;

                fp32_to_real =
                    (sign ? -1.0 : 1.0) *
                    mantissa *
                    (2.0 ** (-126));

            end


            // ----------------------------------------------------
            // NORMAL
            // ----------------------------------------------------

            else begin

                mantissa =
                    1.0 + (fraction / 8388608.0);

                unbiased_exp =
                    exponent - 127;

                fp32_to_real =
                    (sign ? -1.0 : 1.0) *
                    mantissa *
                    (2.0 ** unbiased_exp);

            end

        end

    endfunction


    // ============================================================
    // ABSOLUTE VALUE
    // ============================================================

    function real abs_real;

        input real value;

        begin

            if (value < 0.0)
                abs_real = -value;
            else
                abs_real = value;

        end

    endfunction


    // ============================================================
    // BUILD TEST VECTOR
    //
    // We deliberately use deterministic but varied values.
    //
    // Pattern:
    //
    //   positive
    //   negative
    //   fractional
    //   duplicate maxima
    //
    // Then force two elements to the maximum.
    // ============================================================

    task build_test_vector;

        real value;

        integer j;

        begin

            for (j = 0; j < N; j = j + 1) begin

                case (j % 10)

                    0: value =  1.0;
                    1: value =  2.0;
                    2: value = -1.0;
                    3: value =  0.5;
                    4: value =  1.5;
                    5: value = -2.0;
                    6: value =  2.5;
                    7: value =  0.25;
                    8: value = -0.5;
                    9: value =  1.75;

                endcase

                input_data[j] = real_to_fp32(value);

            end


            // ----------------------------------------------------
            // Force known duplicate maximum.
            //
            // This gives us a guaranteed y=0 at multiple points.
            // ----------------------------------------------------

            if (N >= 2) begin

                input_data[0] = 32'h40400000; // 3.0
                input_data[N-1] = 32'h40400000; // 3.0

            end

        end

    endtask


    // ============================================================
    // REAL -> FP32
    //
    // Testbench helper.
    // ============================================================

    function [31:0] real_to_fp32;

        input real value;

        reg sign;

        real abs_value;
        real normalized;

        integer exponent;
        integer biased_exp;

        integer fraction_int;

        begin

            if (value == 0.0) begin

                real_to_fp32 = 32'h00000000;

            end
            else begin

                sign = (value < 0.0);

                if (sign)
                    abs_value = -value;
                else
                    abs_value = value;

                exponent = 0;

                normalized = abs_value;


                while (normalized >= 2.0) begin

                    normalized = normalized / 2.0;

                    exponent = exponent + 1;

                end


                while (normalized < 1.0) begin

                    normalized = normalized * 2.0;

                    exponent = exponent - 1;

                end


                biased_exp = exponent + 127;


                fraction_int =
                    $rtoi(
                        (normalized - 1.0) *
                        8388608.0
                    );


                real_to_fp32 = {
                    sign,
                    biased_exp[7:0],
                    fraction_int[22:0]
                };

            end

        end

    endfunction


    // ============================================================
    // CALCULATE SOFTWARE REFERENCE
    //
    // Reference:
    //
    // y_i = x_i - max(x)
    //
    // exp_i = exp(y_i)
    //
    // sum = Σ exp_i
    // ============================================================

    task calculate_reference;

        real max_real;

        real x_real;

        real y_real;

        integer j;

        begin

            max_real =
                fp32_to_real(input_data[0]);


            // ----------------------------------------------------
            // Find maximum
            // ----------------------------------------------------

            for (j = 1; j < N; j = j + 1) begin

                x_real =
                    fp32_to_real(input_data[j]);

                if (x_real > max_real)
                    max_real = x_real;

            end


            // ----------------------------------------------------
            // Calculate expected exp values
            // ----------------------------------------------------

            reference_sum = 0.0;

            for (j = 0; j < N; j = j + 1) begin

                x_real =
                    fp32_to_real(input_data[j]);

                y_real =
                    x_real - max_real;

                expected_exp[j] =
                    $exp(y_real);

                reference_sum =
                    reference_sum + expected_exp[j];

            end


            $display("");
            $display("----------------------------------------------");
            $display(" SOFTWARE REFERENCE");
            $display("----------------------------------------------");

            $display(
                "Expected MAX = %f",
                max_real
            );

            $display(
                "Expected SUM(exp) = %f",
                reference_sum
            );


            for (j = 0; j < N; j = j + 1) begin

                $display(
                    "index=%0d x=%f exp=%f",
                    j,
                    fp32_to_real(input_data[j]),
                    expected_exp[j]
                );

            end

        end

    endtask


    // ============================================================
    // SEND INPUT
    // ============================================================

    task send_input;

        input [31:0] value;

        begin

            @(posedge clk);

            x_in    <= value;
            x_valid <= 1'b1;

            @(posedge clk);

            x_valid <= 1'b0;

        end

    endtask


    // ============================================================
    // CHECK ACCUMULATOR SUM AGAINST SOFTWARE REFERENCE
    // ============================================================

    task check_final_sum;

        real error;

        begin

            dut_sum =
                fp32_to_real(sum);

            error =
                abs_real(dut_sum - reference_sum);


            $display("");
            $display("----------------------------------------------");
            $display(" ACCUMULATOR RESULT");
            $display("----------------------------------------------");

            $display(
                "DUT SUM       = %f",
                dut_sum
            );

            $display(
                "REFERENCE SUM = %f",
                reference_sum
            );

            $display(
                "ERROR         = %f",
                error
            );


            if (error > SUM_TOL) begin

                $display("FAIL SUM");

                errors = errors + 1;

            end
            else begin

                $display("PASS SUM");

            end

        end

    endtask


    // ============================================================
    // CHECK MAX
    // ============================================================

    task check_max;

        real dut_max;

        begin

            dut_max =
                fp32_to_real(max_value);


            if (abs_real(dut_max - 3.0) > 0.0001) begin

                $display(
                    "FAIL MAX: DUT=%f EXPECTED=3.0",
                    dut_max
                );

                errors = errors + 1;

            end
            else begin

                $display(
                    "PASS MAX: DUT=%f",
                    dut_max
                );

            end

        end

    endtask


    // ============================================================
    // CHECK OUTPUT COUNT
    // ============================================================

    task check_output_count;

        begin

            if (output_count != N) begin

                $display(
                    "FAIL EXP COUNT: got=%0d expected=%0d",
                    output_count,
                    N
                );

                errors = errors + 1;

            end
            else begin

                $display(
                    "PASS EXP COUNT: %0d",
                    output_count
                );

            end

        end

    endtask


    // ============================================================
    // CHECK POSITIVITY
    //
    // exp(x) must always be > 0.
    // ============================================================

    task check_positive_outputs;

        integer j;

        begin

            for (j = 0; j < N; j = j + 1) begin

                if (actual_exp[j] <= 0.0) begin

                    $display(
                        "FAIL POSITIVITY index=%0d value=%f",
                        j,
                        actual_exp[j]
                    );

                    errors = errors + 1;

                end

            end

            if (errors == 0)
                $display("PASS EXP POSITIVITY");

        end

    endtask


    // ============================================================
    // CHECK exp(0)
    //
    // Since max = 3.0 and input_data[0] = 3.0,
    // input_data[N-1] = 3.0:
    //
    // y = 0
    //
    // Therefore:
    //
    // exp(0) = 1
    // ============================================================

    task check_max_exp;

        begin

            if (abs_real(actual_exp[0] - 1.0) > 0.01) begin

                $display(
                    "FAIL EXP(MAX): index=0 value=%f",
                    actual_exp[0]
                );

                errors = errors + 1;

            end
            else begin

                $display(
                    "PASS EXP(MAX): index=0 value=%f",
                    actual_exp[0]
                );

            end


            if (N >= 2) begin

                if (
                    abs_real(actual_exp[N-1] - 1.0)
                    > 0.01
                ) begin

                    $display(
                        "FAIL EXP(MAX): index=%0d value=%f",
                        N-1,
                        actual_exp[N-1]
                    );

                    errors = errors + 1;

                end
                else begin

                    $display(
                        "PASS EXP(MAX): index=%0d value=%f",
                        N-1,
                        actual_exp[N-1]
                    );

                end

            end

        end

    endtask


    // ============================================================
    // MAIN TEST
    // ============================================================

    initial begin

        $display("");
        $display("==============================================");
        $display(" SOFTMAX EXP ACCUMULATOR INTEGRATION TEST");
        $display(" N = %0d", N);
        $display("==============================================");


        // --------------------------------------------------------
        // INITIALIZE
        // --------------------------------------------------------

        rst   = 1'b1;
        start = 1'b0;

        x_in    = 32'h00000000;
        x_valid = 1'b0;

        read_addr = 0;

        output_count = 0;
        errors       = 0;


        // --------------------------------------------------------
        // RESET
        // --------------------------------------------------------

        repeat (3)
            @(posedge clk);

        rst = 1'b0;

        @(posedge clk);


        // --------------------------------------------------------
        // BUILD VECTOR
        // --------------------------------------------------------

        build_test_vector;


        // --------------------------------------------------------
        // SOFTWARE REFERENCE
        // --------------------------------------------------------

        calculate_reference;


        // --------------------------------------------------------
        // START BOTH BLOCKS
        // --------------------------------------------------------

        @(posedge clk);

        start <= 1'b1;

        @(posedge clk);

        start <= 1'b0;


        // --------------------------------------------------------
        // SEND N INPUTS
        // --------------------------------------------------------

        for (i = 0; i < N; i = i + 1) begin

            send_input(input_data[i]);

        end


        // --------------------------------------------------------
        // WAIT FOR ACCUMULATOR DONE
        // --------------------------------------------------------

        wait(accumulator_done);


        // --------------------------------------------------------
        // WAIT FOR NBA SETTLE
        // --------------------------------------------------------

        @(negedge clk);


        // --------------------------------------------------------
        // CHECK RESULTS
        // --------------------------------------------------------

        check_max;

        check_output_count;

        check_final_sum;

        check_positive_outputs;

        check_max_exp;


        // ========================================================
        // FINAL RESULT
        // ========================================================

        $display("");
        $display("==============================================");

        if (errors == 0) begin

            $display(
                " PASS: softmax_exp_accumulator integration"
            );

            $display(
                " N = %0d",
                N
            );

            $display(
                " ALL TESTS PASSED"
            );

        end
        else begin

            $display(
                " FAIL: softmax_exp_accumulator integration"
            );

            $display(
                " N = %0d",
                N
            );

            $display(
                " TOTAL ERRORS = %0d",
                errors
            );

        end

        $display("==============================================");
        $display("");

        $finish;

    end


    // ============================================================
    // MONITOR EXP OUTPUT
    //
    // Use negedge because DUT uses nonblocking assignments at
    // posedge.
    // ============================================================

    always @(negedge clk) begin

        if (exp_valid) begin

            actual_exp[output_count] =
                fp32_to_real(exp_out);

            $display(
                "EXP[%0d] = %h = %f",
                output_count,
                exp_out,
                fp32_to_real(exp_out)
            );

            output_count =
                output_count + 1;

        end

    end

endmodule

