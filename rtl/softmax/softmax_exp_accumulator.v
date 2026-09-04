`timescale 1ns/1ps

module softmax_exp_accumulator #(
    parameter integer N = 4
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    input  wire [31:0] exp_in,
    input  wire        exp_valid,

    input  wire [ADDR_WIDTH-1:0] read_addr,
    output wire [31:0] exp_out,

    output reg  [31:0] sum,
    output reg         done
);

    // ============================================================
    // COUNTER / ADDRESS WIDTH
    // ============================================================

    localparam integer ADDR_WIDTH =
        (N <= 1) ? 1 : $clog2(N);

    reg [ADDR_WIDTH-1:0] count;

    // ============================================================
    // EXPONENTIAL MEMORY
    // ============================================================

    reg [31:0] exp_mem [0:N-1];

    // ============================================================
    // READ STORED EXPONENTIAL
    // ============================================================

    assign exp_out = exp_mem[read_addr];

    // ============================================================
    // FP32 ADDER
    // ============================================================

    wire [31:0] sum_next;

    fp32_adder u_adder (
        .a      (sum),
        .b      (exp_in),
        .result (sum_next)
    );

    // ============================================================
    // SEQUENTIAL ACCUMULATION
    // ============================================================

    always @(posedge clk)
    begin

        if (rst)
        begin
            sum   <= 32'h00000000;
            count <= {ADDR_WIDTH{1'b0}};
            done  <= 1'b0;
        end

        else if (start)
        begin
            sum   <= 32'h00000000;
            count <= {ADDR_WIDTH{1'b0}};
            done  <= 1'b0;
        end

        else if (exp_valid)
        begin

            // Store exponential
            exp_mem[count] <= exp_in;

            // Accumulate
            sum <= sum_next;

            // Last element
            if (count == N-1)
            begin
                done <= 1'b1;
            end

            // More elements
            else
            begin
                count <= count + 1'b1;
            end
        end

    end

endmodule