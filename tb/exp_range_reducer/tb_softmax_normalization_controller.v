`timescale 1ns/1ps

module tb_softmax_normalization_controller;

    reg clk;
    reg rst;

    // ============================================================
    // N = 4
    // ============================================================

    reg        start4;
    reg [31:0] exp_value4;
    reg [31:0] reciprocal4;

    wire [1:0] read_addr4;
    wire [31:0] softmax_value4;
    wire        softmax_valid4;
    wire        done4;


    softmax_normalization_controller #(
        .N(4)
    ) dut4 (
        .clk          (clk),
        .rst          (rst),
        .start        (start4),
        .exp_value    (exp_value4),
        .reciprocal   (reciprocal4),
        .read_addr    (read_addr4),
        .softmax_value(softmax_value4),
        .softmax_valid(softmax_valid4),
        .done         (done4)
    );


    // ============================================================
    // N = 7
    // ============================================================

    reg        start7;
    reg [31:0] exp_value7;
    reg [31:0] reciprocal7;

    wire [2:0] read_addr7;
    wire [31:0] softmax_value7;
    wire        softmax_valid7;
    wire        done7;


    softmax_normalization_controller #(
        .N(7)
    ) dut7 (
        .clk          (clk),
        .rst          (rst),
        .start        (start7),
        .exp_value    (exp_value7),
        .reciprocal   (reciprocal7),
        .read_addr    (read_addr7),
        .softmax_value(softmax_value7),
        .softmax_valid(softmax_valid7),
        .done          (done7)
    );


    // ============================================================
    // N = 13
    // ============================================================

    reg        start13;
    reg [31:0] exp_value13;
    reg [31:0] reciprocal13;

    wire [3:0] read_addr13;
    wire [31:0] softmax_value13;
    wire        softmax_valid13;
    wire        done13;


    softmax_normalization_controller #(
        .N(13)
    ) dut13 (
        .clk          (clk),
        .rst          (rst),
        .start        (start13),
        .exp_value    (exp_value13),
        .reciprocal   (reciprocal13),
        .read_addr    (read_addr13),
        .softmax_value(softmax_value13),
        .softmax_valid(softmax_valid13),
        .done          (done13)
    );


    // ============================================================
    // N = 16
    // ============================================================

    reg        start16;
    reg [31:0] exp_value16;
    reg [31:0] reciprocal16;

    wire [3:0] read_addr16;
    wire [31:0] softmax_value16;
    wire        softmax_valid16;
    wire        done16;


    softmax_normalization_controller #(
        .N(16)
    ) dut16 (
        .clk          (clk),
        .rst          (rst),
        .start        (start16),
        .exp_value    (exp_value16),
        .reciprocal   (reciprocal16),
        .read_addr    (read_addr16),
        .softmax_value(softmax_value16),
        .softmax_valid(softmax_valid16),
        .done          (done16)
    );


    // ============================================================
    // CLOCK
    // ============================================================

    initial begin
        clk = 0;

        forever #5 clk = ~clk;
    end


    // ============================================================
    // TEST CONTROL
    // ============================================================

    integer errors;


    initial begin

        errors = 0;

        // Initial values
        rst = 1;

        start4  = 0;
        start7  = 0;
        start13 = 0;
        start16 = 0;

        exp_value4  = 32'h00000000;
        exp_value7  = 32'h00000000;
        exp_value13 = 32'h00000000;
        exp_value16 = 32'h00000000;

        reciprocal4  = 32'h3F800000;
        reciprocal7  = 32'h3F800000;
        reciprocal13 = 32'h3F800000;
        reciprocal16 = 32'h3F800000;


        // Reset
        repeat(2) @(posedge clk);
        rst = 0;

        $display("");
        $display("============================================");
        $display(" SOFTMAX NORMALIZATION CONTROLLER TEST");
        $display("============================================");


        // ========================================================
        // N = 4
        // ========================================================

        test_n4;


        // ========================================================
        // N = 7
        // ========================================================

        test_n7;


        // ========================================================
        // N = 13
        // ========================================================

        test_n13;


        // ========================================================
        // N = 16
        // ========================================================

        test_n16;


        // ========================================================
        // FINAL RESULT
        // ========================================================

        $display("");
        $display("============================================");

        if (errors == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" TEST FAILED : %0d errors", errors);

        $display("============================================");

        #20;
        $finish;

    end


    // ============================================================
    // N = 4 TEST
    // ============================================================

    task test_n4;

        integer i;
        reg [31:0] exp_mem [0:3];

        begin

            $display("");
            $display("------------ TEST N = 4 ------------");

            // exp values:
            // 1.0, 0.5, 0.25, 0.125
            exp_mem[0] = 32'h3F800000;
            exp_mem[1] = 32'h3F000000;
            exp_mem[2] = 32'h3E800000;
            exp_mem[3] = 32'h3E000000;

            // reciprocal = 1.0
            reciprocal4 = 32'h3F800000;

            // Start
            @(negedge clk);
            exp_value4 = exp_mem[0];
            start4 = 1;

            @(posedge clk);
            #1;

            if (read_addr4 !== 0) begin
                $display("FAIL N4: expected addr 0, got %0d", read_addr4);
                errors = errors + 1;
            end

            if (!softmax_valid4) begin
                $display("FAIL N4: softmax_valid not asserted");
                errors = errors + 1;
            end

            start4 = 0;


            // Remaining values
            for (i = 1; i < 4; i = i + 1) begin

                @(negedge clk);

                exp_value4 = exp_mem[i];

                @(posedge clk);
                #1;

                if (read_addr4 !== i) begin
                    $display(
                        "FAIL N4: expected addr %0d, got %0d",
                        i,
                        read_addr4
                    );

                    errors = errors + 1;
                end

                if (i < 3 && !softmax_valid4) begin
                    $display(
                        "FAIL N4: valid missing at index %0d",
                        i
                    );

                    errors = errors + 1;
                end

                if (i == 3 && done4 !== 0) begin
                    // done becomes high only on the NEXT controller
                    // clock after the last value.
                end

            end


            // Check completion
            @(posedge clk);
            #1;

            if (!done4) begin
                $display("FAIL N4: done not asserted");
                errors = errors + 1;
            end
            else begin
                $display("PASS N4: done asserted");
            end

            $display("N4 final address = %0d", read_addr4);

        end

    endtask


    // ============================================================
    // N = 7 TEST
    // ============================================================

    task test_n7;

        integer i;
        reg [31:0] exp_mem [0:6];

        begin

            $display("");
            $display("------------ TEST N = 7 ------------");

            exp_mem[0] = 32'h3F800000; // 1
            exp_mem[1] = 32'h3F000000; // 0.5
            exp_mem[2] = 32'h3E800000; // 0.25
            exp_mem[3] = 32'h3E000000; // 0.125
            exp_mem[4] = 32'h3D800000; // 0.0625
            exp_mem[5] = 32'h3D000000; // 0.03125
            exp_mem[6] = 32'h3C800000; // 0.015625

            reciprocal7 = 32'h3F800000;

            @(negedge clk);

            exp_value7 = exp_mem[0];
            start7 = 1;

            @(posedge clk);
            #1;

            if (read_addr7 !== 0) begin
                $display("FAIL N7: expected addr 0, got %0d", read_addr7);
                errors = errors + 1;
            end

            if (!softmax_valid7) begin
                $display("FAIL N7: valid missing at index 0");
                errors = errors + 1;
            end

            start7 = 0;


            for (i = 1; i < 7; i = i + 1) begin

                @(negedge clk);

                exp_value7 = exp_mem[i];

                @(posedge clk);
                #1;

                if (read_addr7 !== i) begin
                    $display(
                        "FAIL N7: expected addr %0d, got %0d",
                        i,
                        read_addr7
                    );

                    errors = errors + 1;
                end

                if (!softmax_valid7) begin
                    $display(
                        "FAIL N7: valid missing at index %0d",
                        i
                    );

                    errors = errors + 1;
                end

            end


            @(posedge clk);
            #1;

            if (!done7) begin
                $display("FAIL N7: done not asserted");
                errors = errors + 1;
            end
            else begin
                $display("PASS N7: done asserted");
            end

        end

    endtask


    // ============================================================
    // N = 13 TEST
    // ============================================================

    task test_n13;

        integer i;
        reg [31:0] exp_mem [0:12];

        begin

            $display("");
            $display("------------ TEST N = 13 ------------");

            exp_mem[0]  = 32'h3F800000;
            exp_mem[1]  = 32'h3F000000;
            exp_mem[2]  = 32'h3E800000;
            exp_mem[3]  = 32'h3E000000;
            exp_mem[4]  = 32'h3D800000;
            exp_mem[5]  = 32'h3D000000;
            exp_mem[6]  = 32'h3C800000;
            exp_mem[7]  = 32'h3C000000;
            exp_mem[8]  = 32'h3B800000;
            exp_mem[9]  = 32'h3B000000;
            exp_mem[10] = 32'h3A800000;
            exp_mem[11] = 32'h3A000000;
            exp_mem[12] = 32'h39800000;

            reciprocal13 = 32'h3F800000;

            @(negedge clk);

            exp_value13 = exp_mem[0];
            start13 = 1;

            @(posedge clk);
            #1;

            if (read_addr13 !== 0) begin
                $display("FAIL N13: expected addr 0, got %0d",
                         read_addr13);
                errors = errors + 1;
            end

            start13 = 0;


            for (i = 1; i < 13; i = i + 1) begin

                @(negedge clk);

                exp_value13 = exp_mem[i];

                @(posedge clk);
                #1;

                if (read_addr13 !== i) begin
                    $display(
                        "FAIL N13: expected addr %0d, got %0d",
                        i,
                        read_addr13
                    );

                    errors = errors + 1;
                end

                if (!softmax_valid13) begin
                    $display(
                        "FAIL N13: valid missing at index %0d",
                        i
                    );

                    errors = errors + 1;
                end

            end


            @(posedge clk);
            #1;

            if (!done13) begin
                $display("FAIL N13: done not asserted");
                errors = errors + 1;
            end
            else begin
                $display("PASS N13: done asserted");
            end

        end

    endtask


    // ============================================================
    // N = 16 TEST
    // ============================================================

    task test_n16;

        integer i;
        reg [31:0] exp_mem [0:15];

        begin

            $display("");
            $display("------------ TEST N = 16 ------------");

            exp_mem[0]  = 32'h3F800000;
            exp_mem[1]  = 32'h3F000000;
            exp_mem[2]  = 32'h3E800000;
            exp_mem[3]  = 32'h3E000000;
            exp_mem[4]  = 32'h3D800000;
            exp_mem[5]  = 32'h3D000000;
            exp_mem[6]  = 32'h3C800000;
            exp_mem[7]  = 32'h3C000000;
            exp_mem[8]  = 32'h3B800000;
            exp_mem[9]  = 32'h3B000000;
            exp_mem[10] = 32'h3A800000;
            exp_mem[11] = 32'h3A000000;
            exp_mem[12] = 32'h39800000;
            exp_mem[13] = 32'h39000000;
            exp_mem[14] = 32'h38800000;
            exp_mem[15] = 32'h38000000;

            reciprocal16 = 32'h3F800000;

            @(negedge clk);

            exp_value16 = exp_mem[0];
            start16 = 1;

            @(posedge clk);
            #1;

            if (read_addr16 !== 0) begin
                $display("FAIL N16: expected addr 0, got %0d",
                         read_addr16);
                errors = errors + 1;
            end

            start16 = 0;


            for (i = 1; i < 16; i = i + 1) begin

                @(negedge clk);

                exp_value16 = exp_mem[i];

                @(posedge clk);
                #1;

                if (read_addr16 !== i) begin
                    $display(
                        "FAIL N16: expected addr %0d, got %0d",
                        i,
                        read_addr16
                    );

                    errors = errors + 1;
                end

                if (!softmax_valid16) begin
                    $display(
                        "FAIL N16: valid missing at index %0d",
                        i
                    );

                    errors = errors + 1;
                end

            end


            @(posedge clk);
            #1;

            if (!done16) begin
                $display("FAIL N16: done not asserted");
                errors = errors + 1;
            end
            else begin
                $display("PASS N16: done asserted");
            end

        end

    endtask


    // ============================================================
    // WAVEFORM
    // ============================================================

    initial begin

        $dumpfile("softmax_normalization_controller.vcd");

        $dumpvars(0, tb_softmax_normalization_controller);

    end

endmodule