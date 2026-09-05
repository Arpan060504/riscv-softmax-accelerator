`timescale 1ns/1ps

module streaming_max_reduce #(
    parameter integer N = 4
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    input  wire [31:0] x_in,
    input  wire        x_valid,

    output reg  [31:0] reduced_out,
    output reg         reduced_valid,

    output reg  [31:0] max_value,

    output reg         busy,
    output reg         done
);

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------

    localparam integer INDEX_WIDTH =
        (N <= 1) ? 1 : $clog2(N);

    // ------------------------------------------------------------
    // States
    // ------------------------------------------------------------

    localparam [1:0]
        IDLE      = 2'd0,
        INPUT     = 2'd1,
        WAIT_MAX  = 2'd2,
        REDUCE    = 2'd3;

    reg [1:0] state;

    // ------------------------------------------------------------
    // Input storage
    // ------------------------------------------------------------

    reg [31:0] x_mem [0:N-1];

    // ------------------------------------------------------------
    // Counters
    // ------------------------------------------------------------

    reg [INDEX_WIDTH-1:0] input_count;
    reg [INDEX_WIDTH-1:0] reduce_count;

    // ------------------------------------------------------------
    // Maximum tracking
    // ------------------------------------------------------------

    reg [31:0] current_max;
    reg        first_input;

    wire [31:0] max_candidate;

    // Existing combinational max_finder
    max_finder u_max_finder (
        .a(current_max),
        .b(x_in),
        .max(max_candidate)
    );

    // ------------------------------------------------------------
    // Maximum subtraction
    //
    // reduced = x - max
    //
    // x - max = x + (-max)
    // ------------------------------------------------------------

    wire [31:0] neg_max;

    assign neg_max = {
        ~max_value[31],
        max_value[30:0]
    };

    wire [31:0] reduced_value;

    fp32_adder u_subtractor (
        .a(x_mem[reduce_count]),
        .b(neg_max),
        .result(reduced_value)
    );

    // ------------------------------------------------------------
    // Sequential control
    // ------------------------------------------------------------

    always @(posedge clk) begin

        if (rst) begin

            state         <= IDLE;

            input_count   <= 0;
            reduce_count  <= 0;

            current_max  <= 32'h00000000;
            max_value    <= 32'h00000000;

            first_input  <= 1'b1;

            reduced_out  <= 32'h00000000;
            reduced_valid <= 1'b0;

            busy         <= 1'b0;
            done         <= 1'b0;

        end
        else begin

            // Default one-cycle pulses
            reduced_valid <= 1'b0;
            done          <= 1'b0;

            case (state)

                // ------------------------------------------------
                // IDLE
                // ------------------------------------------------

                IDLE: begin

                    busy <= 1'b0;

                    if (start) begin

                        state       <= INPUT;

                        input_count <= 0;

                        first_input <= 1'b1;

                        current_max <= 32'h00000000;

                        busy        <= 1'b1;

                    end

                end


                // ------------------------------------------------
                // INPUT
                //
                // Accept N valid inputs.
                // Store every input.
                // Track maximum.
                // ------------------------------------------------

                INPUT: begin

                    busy <= 1'b1;

                    if (x_valid) begin

                        // Store input
                        x_mem[input_count] <= x_in;

                        // First input initializes maximum
                        if (first_input) begin

                            current_max <= x_in;

                            first_input <= 1'b0;

                        end
                        else begin

                            current_max <= max_candidate;

                        end

                        // Last input received
                        if (input_count == N-1) begin

                            state <= WAIT_MAX;

                            input_count <= input_count;

                        end
                        else begin

                            input_count <= input_count + 1'b1;

                        end

                    end

                end


                // ------------------------------------------------
                // WAIT_MAX
                //
                // Needed because current_max is updated using
                // non-blocking assignment on the final INPUT cycle.
                // ------------------------------------------------

                WAIT_MAX: begin

                    busy <= 1'b1;

                    max_value <= current_max;

                    reduce_count <= 0;

                    state <= REDUCE;

                end


                // ------------------------------------------------
                // REDUCE
                //
                // Output:
                //
                // reduced_out = x[i] - max
                //
                // One result per cycle.
                // ------------------------------------------------

                REDUCE: begin

                    busy <= 1'b1;

                    reduced_out <= reduced_value;

                    reduced_valid <= 1'b1;

                    if (reduce_count == N-1) begin

                        state <= IDLE;

                        busy <= 1'b0;

                        done <= 1'b1;

                        reduce_count <= 0;

                    end
                    else begin

                        reduce_count <= reduce_count + 1'b1;

                    end

                end


                default: begin

                    state <= IDLE;
                    busy  <= 1'b0;

                end

            endcase

        end

    end

endmodule