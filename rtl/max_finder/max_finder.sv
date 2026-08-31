module max_finder (
    input  logic        clk,
    input  logic        rst,

    // Start a new maximum calculation
    input  logic        clear,

    // Indicates that data_in is valid this cycle
    input  logic        valid,

    // FP32 input
    input  logic [31:0] data_in,

    // Running / final maximum
    output logic [31:0] max_out
);

    // ------------------------------------------------------------
    // FP32 fields of incoming data
    // ------------------------------------------------------------

    logic        sign_in;
    logic [7:0]  exponent_in;
    logic [22:0] fraction_in;

    assign sign_in     = data_in[31];
    assign exponent_in = data_in[30:23];
    assign fraction_in = data_in[22:0];


    // ------------------------------------------------------------
    // Indicates whether the first valid input has arrived
    // ------------------------------------------------------------

    logic first_valid;


    // ------------------------------------------------------------
    // Running maximum
    // ------------------------------------------------------------

    always_ff @(posedge clk) begin

        if (rst) begin

            max_out    <= 32'h00000000;
            first_valid <= 1'b0;
        end

        else if (clear) begin

            // Start a completely new MAX operation
            max_out     <= 32'h00000000;
            first_valid <= 1'b1;
        end

        else if (valid) begin

            // ----------------------------------------------------
            // First element
            // ----------------------------------------------------

            if (first_valid) begin

                max_out    <= data_in;
                first_valid <= 1'b0;

            end

            // ----------------------------------------------------
            // Subsequent elements
            // ----------------------------------------------------

            else begin

                // ------------------------------------------------
                // Different signs
                // ------------------------------------------------

                if (sign_in != max_out[31]) begin

                    // Positive number is greater
                    if (sign_in == 1'b0)
                        max_out <= data_in;

                end


                // ------------------------------------------------
                // Both positive
                // ------------------------------------------------

                else if (sign_in == 1'b0) begin

                    if (exponent_in > max_out[30:23]) begin

                        max_out <= data_in;

                    end

                    else if (exponent_in == max_out[30:23]) begin

                        if (fraction_in > max_out[22:0])
                            max_out <= data_in;

                    end

                end


                // ------------------------------------------------
                // Both negative
                // ------------------------------------------------

                else begin

                    if (exponent_in < max_out[30:23]) begin

                        max_out <= data_in;

                    end

                    else if (exponent_in == max_out[30:23]) begin

                        if (fraction_in < max_out[22:0])
                            max_out <= data_in;

                    end

                end

            end
        end
    end

endmodule