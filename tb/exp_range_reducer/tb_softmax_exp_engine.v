`timescale 1ns/1ps

module tb_softmax_exp_engine;

    reg clk;
    reg rst;

    integer errors;


    // ============================================================
    // CLOCK
    // ============================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end


    // ============================================================
    // N = 4
    // ============================================================

    reg        start4;
    reg [31:0] x4;
    reg        valid4;

    wire [31:0] exp4;
    wire        exp_valid4;
    wire        done4;

    softmax_exp_engine #(.N(4)) dut4 (
        .clk       (clk),
        .rst       (rst),
        .start     (start4),
        .x_in      (x4),
        .x_valid   (valid4),
        .exp_value (exp4),
        .exp_valid (exp_valid4),
        .done      (done4)
    );


    // ============================================================
    // N = 5
    // ============================================================

    reg        start5;
    reg [31:0] x5;
    reg        valid5;

    wire [31:0] exp5;
    wire        exp_valid5;
    wire        done5;

    softmax_exp_engine #(.N(5)) dut5 (
        .clk       (clk),
        .rst       (rst),
        .start     (start5),
        .x_in      (x5),
        .x_valid   (valid5),
        .exp_value (exp5),
        .exp_valid (exp_valid5),
        .done       (done5)
    );


    // ============================================================
    // N = 7
    // ============================================================

    reg        start7;
    reg [31:0] x7;
    reg        valid7;

    wire [31:0] exp7;
    wire        exp_valid7;
    wire        done7;

    softmax_exp_engine #(.N(7)) dut7 (
        .clk       (clk),
        .rst       (rst),
        .start     (start7),
        .x_in      (x7),
        .x_valid   (valid7),
        .exp_value (exp7),
        .exp_valid (exp_valid7),
        .done       (done7)
    );


    // ============================================================
    // N = 8
    // ============================================================

    reg        start8;
    reg [31:0] x8;
    reg        valid8;

    wire [31:0] exp8;
    wire        exp_valid8;
    wire        done8;

    softmax_exp_engine #(.N(8)) dut8 (
        .clk       (clk),
        .rst       (rst),
        .start     (start8),
        .x_in      (x8),
        .x_valid   (valid8),
        .exp_value (exp8),
        .exp_valid (exp_valid8),
        .done       (done8)
    );


    // ============================================================
    // N = 13
    // ============================================================

    reg        start13;
    reg [31:0] x13;
    reg        valid13;

    wire [31:0] exp13;
    wire        exp_valid13;
    wire        done13;

    softmax_exp_engine #(.N(13)) dut13 (
        .clk       (clk),
        .rst       (rst),
        .start     (start13),
        .x_in      (x13),
        .x_valid   (valid13),
        .exp_value (exp13),
        .exp_valid (exp_valid13),
        .done       (done13)
    );


    // ============================================================
    // N = 16
    // ============================================================

    reg        start16;
    reg [31:0] x16;
    reg        valid16;

    wire [31:0] exp16;
    wire        exp_valid16;
    wire        done16;

    softmax_exp_engine #(.N(16)) dut16 (
        .clk       (clk),
        .rst       (rst),
        .start     (start16),
        .x_in      (x16),
        .x_valid   (valid16),
        .exp_value (exp16),
        .exp_valid (exp_valid16),
        .done       (done16)
    );


    // ============================================================
    // N = 21
    // ============================================================

    reg        start21;
    reg [31:0] x21;
    reg        valid21;

    wire [31:0] exp21;
    wire        exp_valid21;
    wire        done21;

    softmax_exp_engine #(.N(21)) dut21 (
        .clk       (clk),
        .rst       (rst),
        .start     (start21),
        .x_in      (x21),
        .x_valid   (valid21),
        .exp_value (exp21),
        .exp_valid (exp_valid21),
        .done       (done21)
    );


    // ============================================================
    // N = 27
    // ============================================================

    reg        start27;
    reg [31:0] x27;
    reg        valid27;

    wire [31:0] exp27;
    wire        exp_valid27;
    wire        done27;

    softmax_exp_engine #(.N(27)) dut27 (
        .clk       (clk),
        .rst       (rst),
        .start     (start27),
        .x_in      (x27),
        .x_valid   (valid27),
        .exp_value (exp27),
        .exp_valid (exp_valid27),
        .done       (done27)
    );


    // ============================================================
    // N = 32
    // ============================================================

    reg        start32;
    reg [31:0] x32;
    reg        valid32;

    wire [31:0] exp32;
    wire        exp_valid32;
    wire        done32;

    softmax_exp_engine #(.N(32)) dut32 (
        .clk       (clk),
        .rst       (rst),
        .start     (start32),
        .x_in      (x32),
        .x_valid   (valid32),
        .exp_value (exp32),
        .exp_valid (exp_valid32),
        .done       (done32)
    );


    // ============================================================
    // N = 35
    // ============================================================

    reg        start35;
    reg [31:0] x35;
    reg        valid35;

    wire [31:0] exp35;
    wire        exp_valid35;
    wire        done35;

    softmax_exp_engine #(.N(35)) dut35 (
        .clk       (clk),
        .rst       (rst),
        .start     (start35),
        .x_in      (x35),
        .x_valid   (valid35),
        .exp_value (exp35),
        .exp_valid (exp_valid35),
        .done       (done35)
    );


    // ============================================================
    // GENERIC TEST TASK
    // ============================================================

    task test_engine;

        input integer N_TEST;

        begin

            errors = 0;

            $display("");
            $display("--------------------------------------------");
            $display(" TESTING SOFTMAX EXP ENGINE : N = %0d", N_TEST);
            $display("--------------------------------------------");


            // ----------------------------------------------------
            // Reset
            // ----------------------------------------------------

            rst = 1'b1;

            start4  = 0;
            start5  = 0;
            start7  = 0;
            start8  = 0;
            start13 = 0;
            start16 = 0;
            start21 = 0;
            start27 = 0;
            start32 = 0;
            start35 = 0;

            valid4  = 0;
            valid5  = 0;
            valid7  = 0;
            valid8  = 0;
            valid13 = 0;
            valid16 = 0;
            valid21 = 0;
            valid27 = 0;
            valid32 = 0;
            valid35 = 0;

            x4  = 0;
            x5  = 0;
            x7  = 0;
            x8  = 0;
            x13 = 0;
            x16 = 0;
            x21 = 0;
            x27 = 0;
            x32 = 0;
            x35 = 0;

            repeat(2) @(posedge clk);

            rst = 1'b0;


            // ----------------------------------------------------
            // Select appropriate DUT
            // ----------------------------------------------------

            case(N_TEST)

                4: begin

                    @(negedge clk);
                    start4 = 1'b1;

                    @(posedge clk);
                    #1;
                    start4 = 1'b0;

                    repeat(4) begin

                        @(negedge clk);
                        x4     = 32'h00000000;
                        valid4 = 1'b1;

                        @(posedge clk);
                        #1;

                        if (!exp_valid4) begin
                            $display("ERROR N4: exp_valid missing");
                            errors = errors + 1;
                        end

                        valid4 = 1'b0;
                    end

                    #1;

                    if (!done4) begin
                        $display("ERROR N4: done not asserted");
                        errors = errors + 1;
                    end

                end


                5: begin

                    @(negedge clk);
                    start5 = 1'b1;

                    @(posedge clk);
                    #1;
                    start5 = 1'b0;

                    repeat(5) begin

                        @(negedge clk);
                        x5     = 32'h00000000;
                        valid5 = 1'b1;

                        @(posedge clk);
                        #1;

                        if (!exp_valid5) begin
                            $display("ERROR N5: exp_valid missing");
                            errors = errors + 1;
                        end

                        valid5 = 1'b0;
                    end

                    #1;

                    if (!done5) begin
                        $display("ERROR N5: done not asserted");
                        errors = errors + 1;
                    end

                end


                7: begin

                    @(negedge clk);
                    start7 = 1'b1;

                    @(posedge clk);
                    #1;
                    start7 = 1'b0;

                    repeat(7) begin

                        @(negedge clk);
                        x7     = 32'h00000000;
                        valid7 = 1'b1;

                        @(posedge clk);
                        #1;

                        if (!exp_valid7) begin
                            $display("ERROR N7: exp_valid missing");
                            errors = errors + 1;
                        end

                        valid7 = 1'b0;
                    end

                    #1;

                    if (!done7) begin
                        $display("ERROR N7: done not asserted");
                        errors = errors + 1;
                    end

                end


                8: begin

                    @(negedge clk);
                    start8 = 1'b1;

                    @(posedge clk);
                    #1;
                    start8 = 1'b0;

                    repeat(8) begin

                        @(negedge clk);
                        x8     = 32'h00000000;
                        valid8 = 1'b1;

                        @(posedge clk);
                        #1;

                        if (!exp_valid8) begin
                            $display("ERROR N8: exp_valid missing");
                            errors = errors + 1;
                        end

                        valid8 = 1'b0;
                    end

                    #1;

                    if (!done8) begin
                        $display("ERROR N8: done not asserted");
                        errors = errors + 1;
                    end

                end


                13: begin

                    @(negedge clk);
                    start13 = 1'b1;

                    @(posedge clk);
                    #1;
                    start13 = 1'b0;

                    repeat(13) begin

                        @(negedge clk);
                        x13     = 32'h00000000;
                        valid13 = 1'b1;

                        @(posedge clk);
                        #1;

                        if (!exp_valid13) begin
                            $display("ERROR N13: exp_valid missing");
                            errors = errors + 1;
                        end

                        valid13 = 1'b0;
                    end

                    #1;

                    if (!done13) begin
                        $display("ERROR N13: done not asserted");
                        errors = errors + 1;
                    end

                end


                16: begin

                    @(negedge clk);
                    start16 = 1'b1;

                    @(posedge clk);
                    #1;
                    start16 = 1'b0;

                    repeat(16) begin

                        @(negedge clk);
                        x16     = 32'h00000000;
                        valid16 = 1'b1;

                        @(posedge clk);
                        #1;

                        if (!exp_valid16) begin
                            $display("ERROR N16: exp_valid missing");
                            errors = errors + 1;
                        end

                        valid16 = 1'b0;
                    end

                    #1;

                    if (!done16) begin
                        $display("ERROR N16: done not asserted");
                        errors = errors + 1;
                    end

                end


                21: begin

                    @(negedge clk);
                    start21 = 1'b1;

                    @(posedge clk);
                    #1;
                    start21 = 1'b0;

                    repeat(21) begin

                        @(negedge clk);
                        x21     = 32'h00000000;
                        valid21 = 1'b1;

                        @(posedge clk);
                        #1;

                        if (!exp_valid21) begin
                            $display("ERROR N21: exp_valid missing");
                            errors = errors + 1;
                        end

                        valid21 = 1'b0;
                    end

                    #1;

                    if (!done21) begin
                        $display("ERROR N21: done not asserted");
                        errors = errors + 1;
                    end

                end


                27: begin

                    @(negedge clk);
                    start27 = 1'b1;

                    @(posedge clk);
                    #1;
                    start27 = 1'b0;

                    repeat(27) begin

                        @(negedge clk);
                        x27     = 32'h00000000;
                        valid27 = 1'b1;

                        @(posedge clk);
                        #1;

                        if (!exp_valid27) begin
                            $display("ERROR N27: exp_valid missing");
                            errors = errors + 1;
                        end

                        valid27 = 1'b0;
                    end

                    #1;

                    if (!done27) begin
                        $display("ERROR N27: done not asserted");
                        errors = errors + 1;
                    end

                end


                32: begin

                    @(negedge clk);
                    start32 = 1'b1;

                    @(posedge clk);
                    #1;
                    start32 = 1'b0;

                    repeat(32) begin

                        @(negedge clk);
                        x32     = 32'h00000000;
                        valid32 = 1'b1;

                        @(posedge clk);
                        #1;

                        if (!exp_valid32) begin
                            $display("ERROR N32: exp_valid missing");
                            errors = errors + 1;
                        end

                        valid32 = 1'b0;
                    end

                    #1;

                    if (!done32) begin
                        $display("ERROR N32: done not asserted");
                        errors = errors + 1;
                    end

                end


                35: begin

                    @(negedge clk);
                    start35 = 1'b1;

                    @(posedge clk);
                    #1;
                    start35 = 1'b0;

                    repeat(35) begin

                        @(negedge clk);
                        x35     = 32'h00000000;
                        valid35 = 1'b1;

                        @(posedge clk);
                        #1;

                        if (!exp_valid35) begin
                            $display("ERROR N35: exp_valid missing");
                            errors = errors + 1;
                        end

                        valid35 = 1'b0;
                    end

                    #1;

                    if (!done35) begin
                        $display("ERROR N35: done not asserted");
                        errors = errors + 1;
                    end

                end

            endcase


            if (errors == 0)
                $display("PASS N=%0d", N_TEST);
            else
                $display("FAIL N=%0d : %0d errors", N_TEST, errors);

        end

    endtask


    // ============================================================
    // MAIN
    // ============================================================

    initial begin

        errors = 0;

        $dumpfile("softmax_exp_engine.vcd");
        $dumpvars(0, tb_softmax_exp_engine);

        $display("");
        $display("============================================");
        $display(" SOFTMAX EXP ENGINE PARAMETER TEST");
        $display("============================================");


        test_engine(4);
        test_engine(5);
        test_engine(7);
        test_engine(8);
        test_engine(13);
        test_engine(16);
        test_engine(21);
        test_engine(27);
        test_engine(32);
        test_engine(35);


        $display("");
        $display("============================================");
        $display(" ALL EXP ENGINE TESTS COMPLETED");
        $display("============================================");

        #20;
        $finish;

    end

endmodule