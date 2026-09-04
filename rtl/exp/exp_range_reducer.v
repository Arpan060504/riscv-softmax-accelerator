`timescale 1ns/1ps

module exp_range_reducer #(
    parameter integer N = 4
)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    // Input stream
    input  logic [31:0] data_in,
    input  logic        valid_in,

    // Reduced output stream
    output logic [31:0] data_out,
    output logic        valid_out,

    // Status
    output logic        busy,
    output logic        done,

    // Final maximum
    output logic [31:0] max_value
);

    // ============================================================
    // Parameters
    // ============================================================

    localparam integer INDEX_WIDTH = (N <= 1) ? 1 : $clog2(N);

    // ============================================================
    // FSM
    // ============================================================

    typedef enum logic [2:0] {
        IDLE,
        MAX_PASS,
        WAIT_MAX,
        REDUCE_PASS,
        DONE
    } state_t;

    state_t state;

    // ============================================================
    // Input memory
    // ============================================================

    logic [31:0] x_mem [0:N-1];

    // ============================================================
    // Index
    // ============================================================

    logic [INDEX_WIDTH-1:0] index;

    // ============================================================
    // max_finder
    // ============================================================

    logic [31:0] max_out;

    logic max_clear;
    logic max_valid;

    max_finder u_max_finder (
        .clk     (clk),
        .rst     (rst),
        .clear   (max_clear),
        .valid   (max_valid),
        .data_in (data_in),
        .max_out (max_out)
    );

    // ============================================================
    // FP32 subtraction
    //
    // y = x - max
    //
    // x - max = x + (-max)
    // ============================================================

    logic [31:0] neg_max;
    logic [31:0] reduced_value;

    assign neg_max = {
        ~max_value[31],
        max_value[30:0]
    };

    fp32_adder u_subtractor (
        .a      (x_mem[index]),
        .b      (neg_max),
        .result (reduced_value)
    );

    // ============================================================
    // FSM
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            state      <= IDLE;
            index      <= '0;

            data_out   <= 32'h00000000;
            valid_out  <= 1'b0;

            busy       <= 1'b0;
            done       <= 1'b0;

            max_value  <= 32'h00000000;

            max_clear  <= 1'b0;
            max_valid  <= 1'b0;

        end

        else begin

            // ----------------------------------------------------
            // Default pulse signals
            // ----------------------------------------------------

            valid_out <= 1'b0;
            done      <= 1'b0;

            max_clear <= 1'b0;
            max_valid <= 1'b0;


            // ====================================================
            // IDLE
            // ====================================================

            if (state == IDLE) begin

                busy  <= 1'b0;
                index <= '0;

                if (start) begin

                    state <= MAX_PASS;
                    busy  <= 1'b1;
                    index <= '0;

                    max_clear <= 1'b1;

                end

            end


            // ====================================================
            // MAX_PASS
            //
            // Store inputs and find maximum.
            // ====================================================

            else if (state == MAX_PASS) begin

                busy <= 1'b1;

                if (valid_in) begin

                    // Store original input
                    x_mem[index] <= data_in;

                    // Send input to max_finder
                    max_valid <= 1'b1;

                    // Last input
                    if (index == N-1) begin

                        index <= '0;

                        // IMPORTANT:
                        // Wait one cycle for max_finder
                        // to update max_out.
                        state <= WAIT_MAX;

                    end

                    else begin

                        index <= index + 1'b1;

                    end

                end

            end


            // ====================================================
            // WAIT_MAX
            //
            // max_finder has now processed the final input.
            // Capture final maximum.
            // ====================================================

            else if (state == WAIT_MAX) begin

                busy <= 1'b1;

                // Capture final maximum
                max_value <= max_out;

                // Start reduction on next clock
                index <= '0;

                state <= REDUCE_PASS;

            end


            // ====================================================
            // REDUCE_PASS
            //
            // y[i] = x[i] - max
            //
            // One output per clock.
            // ====================================================

            else if (state == REDUCE_PASS) begin

                busy <= 1'b1;

                data_out  <= reduced_value;
                valid_out <= 1'b1;

                if (index == N-1) begin

                    index <= '0;
                    state <= DONE;

                end

                else begin

                    index <= index + 1'b1;

                end

            end


            // ====================================================
            // DONE
            // ====================================================

            else if (state == DONE) begin

                busy <= 1'b0;
                done <= 1'b1;

                state <= IDLE;

            end

        end

    end

endmodule