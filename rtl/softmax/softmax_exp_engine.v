`timescale 1ns/1ps

module softmax_exp_engine #(
    parameter integer N = 4
)(
    input  wire clk,
    input  wire rst,
    input  wire start,

    // ------------------------------------------------------------
    // Streaming input
    // One x value is supplied when x_valid = 1
    // ------------------------------------------------------------
    input  wire [31:0] x_in,
    input  wire        x_valid,

    // ------------------------------------------------------------
    // Exponential output
    // ------------------------------------------------------------
    output reg [31:0] exp_value,
    output reg        exp_valid,

    // ------------------------------------------------------------
    // Status
    // ------------------------------------------------------------
    output reg        done
);

    localparam integer INDEX_WIDTH =
        (N <= 1) ? 1 : $clog2(N);

    reg [INDEX_WIDTH-1:0] x_index;

    // ------------------------------------------------------------
    // EXP UNIT
    // ------------------------------------------------------------

    wire [31:0] exp_calculated;

    exp_unit u_exp_unit (
        .x       (x_in),
        .exp_out (exp_calculated)
    );


    // ------------------------------------------------------------
    // CONTROL
    // ------------------------------------------------------------

    always @(posedge clk)
    begin

        if (rst)
        begin
            x_index   <= {INDEX_WIDTH{1'b0}};
            exp_value <= 32'h00000000;
            exp_valid <= 1'b0;
            done      <= 1'b0;
        end

        else
        begin

            // Default
            exp_valid <= 1'b0;

            // ----------------------------------------------------
            // START
            // ----------------------------------------------------

            if (start)
            begin
                x_index   <= {INDEX_WIDTH{1'b0}};
                exp_value <= 32'h00000000;
                exp_valid <= 1'b0;
                done      <= 1'b0;
            end

            // ----------------------------------------------------
            // PROCESS INPUT
            // ----------------------------------------------------

            else if (!done && x_valid)
            begin

                // Calculate and output exp(x)
                exp_value <= exp_calculated;
                exp_valid <= 1'b1;

                // ------------------------------------------------
                // Last element
                // ------------------------------------------------

                if (x_index == N-1)
                begin
                    done <= 1'b1;
                end

                else
                begin
                    x_index <= x_index + 1'b1;
                end

            end

        end

    end

endmodule