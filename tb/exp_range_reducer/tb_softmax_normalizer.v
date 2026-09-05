`timescale 1ns/1ps

module tb_softmax_normalizer;

    reg clk;
    reg rst;

    // ============================================================
    // N = 4
    // ============================================================

    reg [31:0] exp_in_4;
    reg        exp_valid_4;
    reg [31:0] reciprocal_4;

    wire [31:0] softmax_out_4;
    wire        softmax_valid_4;
    wire        done_4;

    softmax_normalizer #(.N(4)) dut4 (
        .clk           (clk),
        .rst           (rst),
        .exp_in        (exp_in_4),
        .exp_valid     (exp_valid_4),
        .reciprocal    (reciprocal_4),
        .softmax_out   (softmax_out_4),
        .softmax_valid (softmax_valid_4),
        .done          (done_4)
    );


    // ============================================================
    // N = 7
    // ============================================================

    reg [31:0] exp_in_7;
    reg        exp_valid_7;
    reg [31:0] reciprocal_7;

    wire [31:0] softmax_out_7;
    wire        softmax_valid_7;
    wire        done_7;

    softmax_normalizer #(.N(7)) dut7 (
        .clk           (clk),
        .rst           (rst),
        .exp_in        (exp_in_7),
        .exp_valid     (exp_valid_7),
        .reciprocal    (reciprocal_7),
        .softmax_out   (softmax_out_7),
        .softmax_valid (softmax_valid_7),
        .done          (done_7)
    );


    // ============================================================
    // N = 13
    // ============================================================

    reg [31:0] exp_in_13;
    reg        exp_valid_13;
    reg [31:0] reciprocal_13;

    wire [31:0] softmax_out_13;
    wire        softmax_valid_13;
    wire        done_13;

    softmax_normalizer #(.N(13)) dut13 (
        .clk           (clk),
        .rst           (rst),
        .exp_in        (exp_in_13),
        .exp_valid     (exp_valid_13),
        .reciprocal    (reciprocal_13),
        .softmax_out   (softmax_out_13),
        .softmax_valid (softmax_valid_13),
        .done          (done_13)
    );


    // ============================================================
    // CLOCK
    // ============================================================

    always #5 clk = ~clk;


    // ============================================================
    // N = 4 TEST
    //
    // y = [0, -1, -2, -4.3]
    //
    // exp(y) approximately:
    //
    // 1.000000
    // 0.367879
    // 0.135335
    // 0.013569
    //
    // sum       ≈ 1.516783
    // reciprocal≈ 0.659291
    // ============================================================

    task test_N4;

        integer i;

        reg [31:0] exp_values [0:3];
        reg [31:0] expected   [0:3];

        begin

            $display("");
            $display("========================================");
            $display("SOFTMAX NORMALIZER : N = 4");
            $display("========================================");

            // exp(0)
            exp_values[0] = 32'h3F800000;

            // exp(-1)
            exp_values[1] = 32'h3EBC5AB2;

            // exp(-2)
            exp_values[2] = 32'h3E0A8B15;

            // exp(-4.3)
            exp_values[3] = 32'h3C5E6BBD;

            // Expected softmax values
            expected[0] = 32'h3F28D6C5;
            expected[1] = 32'h3EBBC7A5;
            expected[2] = 32'h3E0A2D7A;
            expected[3] = 32'h3B5F6C8F;

            // reciprocal ≈ 0.659291
            reciprocal_4 = 32'h3F28D6C5;

            exp_valid_4 = 1'b0;
            exp_in_4    = 32'h00000000;

            #10;

            for (i = 0; i < 4; i = i + 1) begin

                @(negedge clk);

                exp_in_4    = exp_values[i];
                exp_valid_4 = 1'b1;

                @(posedge clk);
                #1;

                if (softmax_valid_4) begin

                    $display(
                        "N=4 [%0d] exp=%h softmax=%h",
                        i,
                        exp_in_4,
                        softmax_out_4
                    );

                end
                else begin

                    $display(
                        "N=4 [%0d] ERROR: softmax_valid not asserted",
                        i
                    );

                end

                exp_valid_4 = 1'b0;

            end

            if (done_4)
                $display("N=4 DONE : PASS");
            else
                $display("N=4 DONE : FAIL");

        end

    endtask


    // ============================================================
    // N = 7 TEST
    //
    // y =
    // [0, -0.5, -1.2, -2.3, -3.1, -4.3, -5.23]
    // ============================================================

    task test_N7;

        integer i;

        reg [31:0] exp_values [0:6];

        begin

            $display("");
            $display("========================================");
            $display("SOFTMAX NORMALIZER : N = 7");
            $display("========================================");

            exp_values[0] = 32'h3F800000; // exp(0)
            exp_values[1] = 32'h3F13CD3A; // exp(-0.5)
            exp_values[2] = 32'h3EB1A9E6; // exp(-1.2)
            exp_values[3] = 32'h3D9F6B5D; // exp(-2.3)
            exp_values[4] = 32'h3D3A2F8B; // exp(-3.1)
            exp_values[5] = 32'h3C5E6BBD; // exp(-4.3)
            exp_values[6] = 32'h3BAF7B5C; // exp(-5.23)

            // reciprocal ≈ 0.602
            reciprocal_7 = 32'h3F19A6B0;

            exp_valid_7 = 1'b0;
            exp_in_7    = 32'h00000000;

            #10;

            for (i = 0; i < 7; i = i + 1) begin

                @(negedge clk);

                exp_in_7    = exp_values[i];
                exp_valid_7 = 1'b1;

                @(posedge clk);
                #1;

                if (softmax_valid_7) begin

                    $display(
                        "N=7 [%0d] exp=%h softmax=%h",
                        i,
                        exp_in_7,
                        softmax_out_7
                    );

                end
                else begin

                    $display(
                        "N=7 [%0d] ERROR: softmax_valid not asserted",
                        i
                    );

                end

                exp_valid_7 = 1'b0;

            end

            if (done_7)
                $display("N=7 DONE : PASS");
            else
                $display("N=7 DONE : FAIL");

        end

    endtask


    // ============================================================
    // N = 13 TEST
    // ============================================================

    task test_N13;

        integer i;

        reg [31:0] exp_values [0:12];

        begin

            $display("");
            $display("========================================");
            $display("SOFTMAX NORMALIZER : N = 13");
            $display("========================================");

            exp_values[0]  = 32'h3F800000; // exp(0)
            exp_values[1]  = 32'h3F5EAAE6; // exp(-0.25)
            exp_values[2]  = 32'h3F2BC8F8; // exp(-0.7)
            exp_values[3]  = 32'h3EDB3C5E; // exp(-1.1)
            exp_values[4]  = 32'h3E1E4C9F; // exp(-1.8)
            exp_values[5]  = 32'h3D8F3A2E; // exp(-2.4)
            exp_values[6]  = 32'h3D0B8F2E; // exp(-2.9)
            exp_values[7]  = 32'h3CE6B9F3; // exp(-3.5)
            exp_values[8]  = 32'h3C5E6BBD; // exp(-4.0)
            exp_values[9]  = 32'h3C5E6BBD; // exp(-4.3) placeholder
            exp_values[10] = 32'h3C1A2B3C; // exp(-4.7)
            exp_values[11] = 32'h3BAF7B5C; // exp(-5.23)
            exp_values[12] = 32'h3B24B4B0; // exp(-6.0)

            // Approximate reciprocal
            reciprocal_13 = 32'h3F0A4F20;

            exp_valid_13 = 1'b0;
            exp_in_13    = 32'h00000000;

            #10;

            for (i = 0; i < 13; i = i + 1) begin

                @(negedge clk);

                exp_in_13    = exp_values[i];
                exp_valid_13 = 1'b1;

                @(posedge clk);
                #1;

                if (softmax_valid_13) begin

                    $display(
                        "N=13 [%0d] exp=%h softmax=%h",
                        i,
                        exp_in_13,
                        softmax_out_13
                    );

                end
                else begin

                    $display(
                        "N=13 [%0d] ERROR: softmax_valid not asserted",
                        i
                    );

                end

                exp_valid_13 = 1'b0;

            end

            if (done_13)
                $display("N=13 DONE : PASS");
            else
                $display("N=13 DONE : FAIL");

        end

    endtask


    // ============================================================
    // MAIN
    // ============================================================

    initial begin

        clk = 1'b0;
        rst = 1'b1;

        exp_valid_4  = 1'b0;
        exp_valid_7  = 1'b0;
        exp_valid_13 = 1'b0;

        #20;

        rst = 1'b0;

        test_N4;
        test_N7;
        test_N13;

        $display("");
        $display("========================================");
        $display("ALL TESTS COMPLETE");
        $display("========================================");

        #20;

        $finish;

    end
initial 
    begin
        $dumpfile("softmax_norm.vcd");
        $dumpvars(0, tb_softmax_normalizer);
    end
    
endmodule