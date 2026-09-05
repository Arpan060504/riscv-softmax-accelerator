`timescale 1ns/1ps

module softmax_base2 #(
    parameter integer N = 4
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    // ============================================================
    // STREAMING INPUT
    // One input element is accepted whenever x_valid = 1
    // ============================================================
    input  wire [31:0] x_in,
    input  wire        x_valid,

    // ============================================================
    // STREAMING OUTPUT
    // One softmax element is produced whenever softmax_valid = 1
    // ============================================================
    output wire [31:0] softmax_out,
    output wire        softmax_valid,

    // Asserted for one clock after the complete vector is done
    output wire        done
);

    // ============================================================
    // PARAMETERS
    // ============================================================
    localparam integer INDEX_WIDTH =
                    (N <= 1) ? 1 : $clog2(N);

    // ============================================================
    // TOP-LEVEL FSM
    //
    // IDLE
    //   |
    //   v
    // INPUT
    //   |
    //   v
    // WAIT_EXP
    //   |
    //   v
    // NORMALIZE
    //   |
    //   v
    // DONE
    // ============================================================
    localparam [2:0]
        S_IDLE      = 3'd0,
        S_INPUT     = 3'd1,
        S_WAIT_EXP  = 3'd2,
        S_NORMALIZE = 3'd3,
        S_DONE      = 3'd4;

    reg [2:0] state;

    // Number of input samples accepted
    reg [INDEX_WIDTH-1:0] input_count;

    // Number of output samples generated
    reg [INDEX_WIDTH-1:0] output_count;

    // ============================================================
    // 1. MAX + SUBTRACTION / RANGE REDUCTION
    //
    // Input:
    //      x_in
    //
    // Output:
    //      y = x - max(x)
    //
    // The exp_range_reducer internally stores the input vector,
    // finds the maximum, and then produces the reduced values.
    // ============================================================

    wire [31:0] reduced_value;
    wire        reduced_valid;
    wire        reduced_busy;
    wire        reduced_done;
    wire [31:0] max_value;

    reg         range_start;
    reg         range_valid;

    exp_range_reducer #(
        .N(N)
    ) u_exp_range_reducer (
        .clk       (clk),
        .rst       (rst),

        .start     (range_start),

        .data_in   (x_in),
        .valid_in  (range_valid),

        .data_out  (reduced_value),
        .valid_out (reduced_valid),

        .busy      (reduced_busy),
        .done      (reduced_done),

        .max_value (max_value)
    );


    // ============================================================
    // 2. EXPONENT RANGE REDUCTION
    //
    //      y = k*ln(2) + r
    //
    // exp_kr_reducer is your verified module.
    // DO NOT modify exp_kr_reducer.v.
    // ============================================================

    wire signed [7:0] k_value;
    wire        [31:0] r_value;

    exp_kr_reducer u_exp_kr_reducer (
        .y (reduced_value),
        .k (k_value),
        .r (r_value)
    );


    // ============================================================
    // 3. exp(r)
    // ============================================================

    wire [31:0] exp_r_value;

    exp_r_lut u_exp_r_lut (
        .r     (r_value),
        .exp_r  (exp_r_value)
    );


    // ============================================================
    // 4. exp(y) = 2^k * exp(r)
    // ============================================================

    wire [31:0] exp_value;

    exp_power_of_two u_exp_power_of_two (
        .exp_r   (exp_r_value),
        .k       (k_value),
        .exp_out (exp_value)
    );


    // ============================================================
    // 5. EXPONENTIAL ACCUMULATOR
    //
    // Stores:
    //
    //      exp[0], exp[1], ... exp[N-1]
    //
    // and calculates:
    //
    //      sum = Σ exp[i]
    //
    // exp_mem is later read back during normalization.
    // ============================================================

    wire [31:0] exp_sum;
    wire [31:0] stored_exp_value;
    wire        exp_acc_done;

    reg         accumulator_start;

    reg [INDEX_WIDTH-1:0] read_addr;

    softmax_exp_accumulator #(
        .N(N)
    ) u_exp_accumulator (
        .clk       (clk),
        .rst       (rst),

        .start     (accumulator_start),

        .exp_in    (exp_value),
        .exp_valid (reduced_valid),

        .read_addr (read_addr),

        .exp_out   (stored_exp_value),

        .sum       (exp_sum),
        .done      (exp_acc_done)
    );


    // ============================================================
    // 6. RECIPROCAL
    //
    //      reciprocal = 1 / Σexp
    //
    // This is combinational in the current reciprocal wrapper.
    // ============================================================

    wire [31:0] reciprocal;

    softmax_reciprocal u_softmax_reciprocal (
        .sum        (exp_sum),
        .reciprocal (reciprocal)
    );


    // ============================================================
    // 7. NORMALIZATION
    //
    //      softmax[i] = exp[i] * reciprocal
    //
    // The normalizer is streaming and parameterized.
    // ============================================================

    reg         normalize_valid;

    wire [31:0] normalized_value;
    wire        normalized_valid_internal;
    wire        normalized_done;

    softmax_normalizer #(
        .N(N)
    ) u_softmax_normalizer (
        .clk          (clk),
        .rst          (rst),

        .exp_in       (stored_exp_value),
        .exp_valid    (normalize_valid),

        .reciprocal   (reciprocal),

        .softmax_out  (normalized_value),
        .softmax_valid(normalized_valid_internal),
        .done         (normalized_done)
    );


    // ============================================================
    // OUTPUT ASSIGNMENTS
    // ============================================================

    assign softmax_out   = normalized_value;
    assign softmax_valid = normalized_valid_internal;

    assign done = (state == S_DONE);


    // ============================================================
    // MAIN CONTROLLER
    // ============================================================

    always @(posedge clk) begin

        if (rst) begin

            state              <= S_IDLE;

            input_count        <= {INDEX_WIDTH{1'b0}};
            output_count       <= {INDEX_WIDTH{1'b0}};

            read_addr          <= {INDEX_WIDTH{1'b0}};

            range_start        <= 1'b0;
            range_valid        <= 1'b0;

            accumulator_start  <= 1'b0;
            normalize_valid    <= 1'b0;

        end

        else begin

            // ----------------------------------------------------
            // Default control signals
            // ----------------------------------------------------

            range_start       <= 1'b0;
            range_valid       <= 1'b0;
            accumulator_start <= 1'b0;
            normalize_valid   <= 1'b0;


            // ====================================================
            // IDLE
            // ====================================================

            case (state)

                S_IDLE: begin

                    input_count  <= {INDEX_WIDTH{1'b0}};
                    output_count <= {INDEX_WIDTH{1'b0}};
                    read_addr    <= {INDEX_WIDTH{1'b0}};

                    if (start) begin

                        // Start the range reducer.
                        //
                        // Important:
                        // The actual x_valid data starts on the
                        // following clock because the reducer
                        // changes from IDLE -> MAX_PASS on start.

                        range_start       <= 1'b1;
                        accumulator_start <= 1'b1;

                        input_count <= {INDEX_WIDTH{1'b0}};

                        state <= S_INPUT;

                    end

                end


                // =================================================
                // INPUT
                //
                // Receive:
                //
                // x[0]
                // x[1]
                // ...
                // x[N-1]
                //
                // whenever x_valid = 1.
                // =================================================

                S_INPUT: begin

                    if (x_valid) begin

                        range_valid <= 1'b1;

                        if (input_count == N-1) begin

                            input_count <= input_count;

                            state <= S_WAIT_EXP;

                        end

                        else begin

                            input_count <= input_count + 1'b1;

                        end

                    end

                end


                // =================================================
                // WAIT FOR EXPONENTIAL ACCUMULATION
                //
                // exp_range_reducer produces reduced_value.
                //
                // reduced_value
                //      ↓
                // exp_kr_reducer
                //      ↓
                // exp_r_lut
                //      ↓
                // exp_power_of_two
                //      ↓
                // exp_accumulator
                //
                // exp_accumulator asserts exp_acc_done after N
                // exponential values have been accumulated.
                // =================================================

                S_WAIT_EXP: begin

                    if (exp_acc_done) begin

                        // Start reading exp_mem from element 0.
                        read_addr    <= {INDEX_WIDTH{1'b0}};

                        output_count <= {INDEX_WIDTH{1'b0}};

                        state <= S_NORMALIZE;

                    end

                end


                // =================================================
                // NORMALIZATION
                //
                // stored_exp_value = exp_mem[read_addr]
                //
                // softmax =
                //
                //      exp_mem[i] * (1/sum)
                //
                // One value per cycle.
                // =================================================

                S_NORMALIZE: begin

                    normalize_valid <= 1'b1;

                    if (output_count == N-1) begin

                        output_count <= output_count;

                        state <= S_DONE;

                    end

                    else begin

                        output_count <= output_count + 1'b1;

                        read_addr <= read_addr + 1'b1;

                    end

                end


                // =================================================
                // DONE
                //
                // done is high while state == S_DONE.
                //
                // Return to IDLE after one cycle.
                // =================================================

                S_DONE: begin

                    state <= S_IDLE;

                end


                // =================================================
                // DEFAULT
                // =================================================

                default: begin

                    state <= S_IDLE;

                end

            endcase

        end

    end

endmodule