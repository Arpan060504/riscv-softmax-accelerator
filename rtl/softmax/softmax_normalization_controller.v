`timescale 1ns/1ps

module softmax_normalization_controller #(
    parameter integer N = 4
)(
    input        clk,
    input        rst,
    input        start,

    // Exponential value read from RAM
    input  [31:0] exp_value,

    // 1 / sum(exp)
    input  [31:0] reciprocal,

    // RAM read interface
    output reg [(N <= 1 ? 1 : $clog2(N))-1:0] read_addr,

    // Normalized output
    output [31:0] softmax_value,

    // Indicates that softmax_value is valid
    output reg softmax_valid,

    // Indicates all N values are processed
    output reg done
);

    // ============================================================
    // PARAMETERS
    // ============================================================

    localparam integer INDEX_WIDTH =
        (N <= 1) ? 1 : $clog2(N);


    // ============================================================
    // NORMALIZATION DATAPATH
    // ============================================================

    softmax_normalization_stage normalizer (
        .exp_value     (exp_value),
        .reciprocal    (reciprocal),
        .softmax_value (softmax_value)
    );


    // ============================================================
    // CONTROL
    // ============================================================

    always @(posedge clk)
    begin

        if (rst)
        begin
            read_addr     <= {INDEX_WIDTH{1'b0}};
            softmax_valid <= 1'b0;
            done          <= 1'b0;
        end

        else
        begin

            // Default: output invalid
            softmax_valid <= 1'b0;


            // ----------------------------------------------------
            // START
            // ----------------------------------------------------

            if (start)
            begin
                read_addr     <= {INDEX_WIDTH{1'b0}};
                softmax_valid <= 1'b1;
                done          <= 1'b0;
            end


            // ----------------------------------------------------
            // NORMAL OPERATION
            // ----------------------------------------------------

            else if (!done)
            begin

                if (read_addr < N-1)
                begin
                    read_addr     <= read_addr + 1'b1;
                    softmax_valid <= 1'b1;
                end

                else
                begin
                    // Last value processed
                    read_addr     <= read_addr;
                    softmax_valid <= 1'b0;
                    done          <= 1'b1;
                end

            end

        end

    end

endmodule