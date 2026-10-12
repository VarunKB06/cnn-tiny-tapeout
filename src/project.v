

// ============================================================
// INT4 Processing Element
// Signed 4-bit multiply with a signed accumulator.
// ACC_WIDTH=10 is required for four INT4 products because
// (-8)*(-8)*4 = +256, which does not fit in signed 9-bit.
// ============================================================
module pe #(
    parameter DATA_WIDTH = 4,
    parameter ACC_WIDTH  = 10
)(
    input  wire clk,
    input  wire rst,
    input  wire compute_en,

    input  wire signed [DATA_WIDTH-1:0] data_in,
    input  wire signed [DATA_WIDTH-1:0] weight_in,
    input  wire signed [ACC_WIDTH-1:0]  psum_in,

    output reg signed [DATA_WIDTH-1:0] data_out,
    output reg signed [ACC_WIDTH-1:0]  psum_out
);

    localparam PRODUCT_WIDTH = 2 * DATA_WIDTH;

    wire signed [PRODUCT_WIDTH-1:0] mult_result;
    wire signed [ACC_WIDTH-1:0] mult_extended;

    // Signed INT4 multiplication produces an 8-bit product.
    assign mult_result = data_in * weight_in;

    // Sign-extend the product when the accumulator is wider;
    // truncate only if a deliberately narrower accumulator is selected.
    generate
        if (ACC_WIDTH >= PRODUCT_WIDTH) begin : gen_sign_extend
            assign mult_extended = {
                {(ACC_WIDTH-PRODUCT_WIDTH){mult_result[PRODUCT_WIDTH-1]}},
                mult_result
            };
        end
        else begin : gen_truncate
            assign mult_extended = mult_result[ACC_WIDTH-1:0];
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            data_out   <= 0;
            
            psum_out   <= 0;
        end
        else begin
            // Registered systolic forwarding.
            data_out   <= data_in;
            

            // Pass the accumulated partial sum to the next PE.
            if (compute_en)
                psum_out <= psum_in + mult_extended;
        end
    end

endmodule



module systolic_array #(
    parameter DATA_WIDTH = 4,
    parameter ACC_WIDTH  = 10
)(
    input wire clk,
    input wire rst,
    input wire clear,
    input wire compute_en,
    input wire [1:0] feature_select,

    input wire signed [DATA_WIDTH-1:0] feature_0,
    input wire signed [DATA_WIDTH-1:0] feature_1,
    input wire signed [DATA_WIDTH-1:0] feature_2,
    input wire signed [DATA_WIDTH-1:0] feature_3,

    input wire signed [DATA_WIDTH-1:0] weight_0,
    input wire signed [DATA_WIDTH-1:0] weight_1,
    input wire signed [DATA_WIDTH-1:0] weight_2,
    input wire signed [DATA_WIDTH-1:0] weight_3,

    output wire signed [ACC_WIDTH-1:0] row_result
);

    // Select one feature row at a time.
    reg signed [DATA_WIDTH-1:0] selected_feature;

    always @* begin
        case (feature_select)
            2'd0: selected_feature = feature_0;
            2'd1: selected_feature = feature_1;
            2'd2: selected_feature = feature_2;
            2'd3: selected_feature = feature_3;
            default: selected_feature = {DATA_WIDTH{1'b0}};
        endcase
    end

    // Local clear resets the pipeline between feature rows.
    wire pe_rst;
    assign pe_rst = rst | clear;

    // Four PEs connected as a registered 1x4 MAC chain.
    wire signed [DATA_WIDTH-1:0] feature_fwd_0;
    wire signed [DATA_WIDTH-1:0] feature_fwd_1;
    wire signed [DATA_WIDTH-1:0] feature_fwd_2;

    wire signed [ACC_WIDTH-1:0] psum_0;
    wire signed [ACC_WIDTH-1:0] psum_1;
    wire signed [ACC_WIDTH-1:0] psum_2;

    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) pe_0 (
        .clk(clk),
        .rst(pe_rst),
        .compute_en(compute_en),
        .data_in(selected_feature),
        .weight_in(weight_0),
        .psum_in({ACC_WIDTH{1'b0}}),
        .data_out(feature_fwd_0),
        
        .psum_out(psum_0)
    );

    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) pe_1 (
        .clk(clk),
        .rst(pe_rst),
        .compute_en(compute_en),
        .data_in(feature_fwd_0),
        .weight_in(weight_1),
        .psum_in(psum_0),
        .data_out(feature_fwd_1),
        
        .psum_out(psum_1)
    );

    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) pe_2 (
        .clk(clk),
        .rst(pe_rst),
        .compute_en(compute_en),
        .data_in(feature_fwd_1),
        .weight_in(weight_2),
        .psum_in(psum_1),
        .data_out(feature_fwd_2),
       
        .psum_out(psum_2)
    );

    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) pe_3 (
        .clk(clk),
        .rst(pe_rst),
        .compute_en(compute_en),
        .data_in(feature_fwd_2),
        .weight_in(weight_3),
        .psum_in(psum_2),
        .data_out(),
        
        .psum_out(row_result)
    );

endmodule




module controller_fsm #(
    parameter COMPUTE_CYCLES = 4
)(
    input  wire clk,
    input  wire rst,
    input  wire start,

    output wire compute_en,
    output wire clear,
    output wire [1:0] feature_select,
    output wire capture,
    output wire done,
    output wire busy
);

    // Controller states
    localparam IDLE      = 3'd0;
    localparam CLEAR_ROW = 3'd1;
    localparam COMPUTE   = 3'd2;
    localparam CAPTURE   = 3'd3;
    localparam FINISH    = 3'd4;

    reg [2:0] state;
    reg [1:0] row_index;

   localparam COUNT_WIDTH =
    (COMPUTE_CYCLES > 1) ? $clog2(COMPUTE_CYCLES) : 1;

localparam [COUNT_WIDTH-1:0] LAST_CYCLE =
    COUNT_WIDTH'(COMPUTE_CYCLES - 1);

reg [COUNT_WIDTH-1:0] cycle_count;

    // Control signals for the PE array
    assign compute_en   = (state == COMPUTE);
    assign clear        = (state == CLEAR_ROW);
    assign feature_select = row_index;
    assign capture      = (state == CAPTURE);
    assign done         = (state == FINISH);
    assign busy         = (state != IDLE) && (state != FINISH);

    always @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
            row_index   <= 2'd0;
            cycle_count <= 0;
        end
        else begin
            case (state)

                IDLE: begin
                    row_index   <= 2'd0;
                    cycle_count <= 0;

                    if (start)
                        state <= CLEAR_ROW;
                end

                // Clear all four PEs before processing a new row.
                CLEAR_ROW: begin
                    cycle_count <= 0;
                    state       <= COMPUTE;
                end

                // Four registered PEs require four enabled cycles
                // for the result to emerge from the final PE.
                COMPUTE: begin
                   if (cycle_count == LAST_CYCLE) begin
                        cycle_count <= 0;
                        state       <= CAPTURE;
                    end
                    else begin
                        cycle_count <= cycle_count + 1'b1;
                    end
                end

                // The top module captures row_result while capture
                // is asserted.
                CAPTURE: begin
                    if (row_index == 2'd3) begin
                        state <= FINISH;
                    end
                    else begin
                        row_index <= row_index + 1'b1;
                        state     <= CLEAR_ROW;
                    end
                end

                FINISH: begin
                    state <= IDLE;
                end

                default: begin
                    state       <= IDLE;
                    row_index   <= 2'd0;
                    cycle_count <= 0;
                end

            endcase
        end
    end

endmodule



module cnn_accelerator_top #(
    parameter DATA_WIDTH     = 4,
    parameter ACC_WIDTH      = 10,
    parameter COMPUTE_CYCLES = 4
)(
    input wire clk,
    input wire rst,
    input wire start,

    input wire signed [DATA_WIDTH-1:0] feature_0,
    input wire signed [DATA_WIDTH-1:0] feature_1,
    input wire signed [DATA_WIDTH-1:0] feature_2,
    input wire signed [DATA_WIDTH-1:0] feature_3,

    input wire signed [DATA_WIDTH-1:0] weight_0,
    input wire signed [DATA_WIDTH-1:0] weight_1,
    input wire signed [DATA_WIDTH-1:0] weight_2,
    input wire signed [DATA_WIDTH-1:0] weight_3,

    output reg signed [ACC_WIDTH-1:0] output_0,
    output reg signed [ACC_WIDTH-1:0] output_1,
    output reg signed [ACC_WIDTH-1:0] output_2,
    output reg signed [ACC_WIDTH-1:0] output_3,

    output wire output_valid,
    output wire done,
    output wire busy
);

    // Controller-to-array signals
    wire compute_en;
    wire clear;
    wire capture;
    wire [1:0] feature_select;

    // Result from the reusable four-PE MAC chain
    wire signed [ACC_WIDTH-1:0] row_result;

    // ------------------------------------------------
    // Controller: process four feature rows sequentially
    // ------------------------------------------------
    controller_fsm #(
        .COMPUTE_CYCLES(COMPUTE_CYCLES)
    ) u_controller (
        .clk(clk),
        .rst(rst),
        .start(start),
        .compute_en(compute_en),
        .clear(clear),
        .feature_select(feature_select),
        .capture(capture),
        .done(done),
        .busy(busy)
    );

    // ------------------------------------------------
    // Four reusable INT4 processing elements
    // ------------------------------------------------
    systolic_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_systolic_array (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .compute_en(compute_en),
        .feature_select(feature_select),

        .feature_0(feature_0),
        .feature_1(feature_1),
        .feature_2(feature_2),
        .feature_3(feature_3),

        .weight_0(weight_0),
        .weight_1(weight_1),
        .weight_2(weight_2),
        .weight_3(weight_3),

        .row_result(row_result)
    );

    // ------------------------------------------------
    // Store the result for each feature row separately
    // ------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            output_0 <= 0;
            output_1 <= 0;
            output_2 <= 0;
            output_3 <= 0;
        end
        else if (capture) begin
            case (feature_select)
                2'd0: output_0 <= row_result;
                2'd1: output_1 <= row_result;
                2'd2: output_2 <= row_result;
                2'd3: output_3 <= row_result;
                default: begin
                end
            endcase
        end
    end

    // Results become valid when all four rows are complete.
    assign output_valid = done;

endmodule



module tt_um_cnn_accelerator (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ena,

    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,

    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe
);

    // Commands: uio_in[1:0]
    
    localparam CMD_LOAD  = 2'b01;
    localparam CMD_START = 2'b10;
    localparam CMD_READ  = 2'b11;

    // Wrapper states
    localparam ST_LOAD    = 2'b00;
    localparam ST_COMPUTE = 2'b01;
    localparam ST_OUTPUT  = 2'b10;

    reg [1:0] state;
    reg [2:0] load_count;
    reg [2:0] output_count;
    reg       inputs_loaded;

    // Four signed INT4 feature values
    reg signed [3:0] feature_0;
    reg signed [3:0] feature_1;
    reg signed [3:0] feature_2;
    reg signed [3:0] feature_3;

    // Four signed INT4 weight values
    reg signed [3:0] weight_0;
    reg signed [3:0] weight_1;
    reg signed [3:0] weight_2;
    reg signed [3:0] weight_3;

    reg start;

    // Four signed 10-bit outputs
    wire signed [9:0] output_0;
    wire signed [9:0] output_1;
    wire signed [9:0] output_2;
    wire signed [9:0] output_3;

    wire output_valid;
    wire done;
    wire busy;

    // Sign-extend each output to 16 bits for byte reading
    wire signed [15:0] output_0_ext;
    wire signed [15:0] output_1_ext;
    wire signed [15:0] output_2_ext;
    wire signed [15:0] output_3_ext;

    assign output_0_ext = {{6{output_0[9]}}, output_0};
    assign output_1_ext = {{6{output_1[9]}}, output_1};
    assign output_2_ext = {{6{output_2[9]}}, output_2};
    assign output_3_ext = {{6{output_3[9]}}, output_3};

    // Status pins: bit 2 = busy, bit 3 = output_valid
    assign uio_out = {4'b0000, output_valid, busy, 2'b00};
    assign uio_oe  = 8'b0000_1100;

    // ------------------------------------------------
    // Resource-shared 4x4 INT4 accelerator
    // Four PEs reused for four feature rows
    // ------------------------------------------------

    cnn_accelerator_top #(
        .DATA_WIDTH(4),
        .ACC_WIDTH(10),
        .COMPUTE_CYCLES(4)
    ) u_accelerator (
        .clk(clk),
        .rst(~rst_n),
        .start(start),

        .feature_0(feature_0),
        .feature_1(feature_1),
        .feature_2(feature_2),
        .feature_3(feature_3),

        .weight_0(weight_0),
        .weight_1(weight_1),
        .weight_2(weight_2),
        .weight_3(weight_3),

        .output_0(output_0),
        .output_1(output_1),
        .output_2(output_2),
        .output_3(output_3),

        .output_valid(output_valid),
        .done(done),
        .busy(busy)
    );

    // ------------------------------------------------
    // Input loading and command control
    //
    // Load order:
    // 0: feature_0
    // 1: feature_1
    // 2: feature_2
    // 3: feature_3
    // 4: weight_0
    // 5: weight_1
    // 6: weight_2
    // 7: weight_3
    //
    // INT4 input is ui_in[3:0].
    // Each command is one clock cycle, followed by IDLE.
    // ------------------------------------------------

    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= ST_LOAD;
            load_count    <= 3'd0;
            output_count  <= 3'd0;
            inputs_loaded <= 1'b0;

            feature_0 <= 4'sd0;
            feature_1 <= 4'sd0;
            feature_2 <= 4'sd0;
            feature_3 <= 4'sd0;

            weight_0 <= 4'sd0;
            weight_1 <= 4'sd0;
            weight_2 <= 4'sd0;
            weight_3 <= 4'sd0;

            start <= 1'b0;
        end
        else begin
            // Default: one-cycle start pulse
            start <= 1'b0;

            if (ena) begin
                case (state)

                    ST_LOAD: begin
                        if ((uio_in[1:0] == CMD_LOAD) &&
                            !inputs_loaded) begin

                            case (load_count)
                                3'd0: feature_0 <= $signed(ui_in[3:0]);
                                3'd1: feature_1 <= $signed(ui_in[3:0]);
                                3'd2: feature_2 <= $signed(ui_in[3:0]);
                                3'd3: feature_3 <= $signed(ui_in[3:0]);
                                3'd4: weight_0  <= $signed(ui_in[3:0]);
                                3'd5: weight_1  <= $signed(ui_in[3:0]);
                                3'd6: weight_2  <= $signed(ui_in[3:0]);
                                3'd7: weight_3  <= $signed(ui_in[3:0]);
                                default: begin
                                end
                            endcase

                            if (load_count == 3'd7) begin
                                inputs_loaded <= 1'b1;
                                load_count    <= 3'd0;
                            end
                            else begin
                                load_count <= load_count + 1'b1;
                            end
                        end

                        if ((uio_in[1:0] == CMD_START) &&
                            inputs_loaded) begin

                            start        <= 1'b1;
                            output_count <= 3'd0;
                            state        <= ST_COMPUTE;
                        end
                    end

                    ST_COMPUTE: begin
                        if (done) begin
                            output_count <= 3'd0;
                            state        <= ST_OUTPUT;
                        end
                    end

                    ST_OUTPUT: begin
                        if (uio_in[1:0] == CMD_READ) begin
                            if (output_count == 3'd7) begin
                                // All eight result bytes were read
                                state         <= ST_LOAD;
                                load_count    <= 3'd0;
                                inputs_loaded <= 1'b0;
                                output_count  <= 3'd0;
                            end
                            else begin
                                output_count <= output_count + 1'b1;
                            end
                        end
                    end

                    default: begin
                        state         <= ST_LOAD;
                        load_count    <= 3'd0;
                        output_count  <= 3'd0;
                        inputs_loaded <= 1'b0;
                        start         <= 1'b0;
                    end

                endcase
            end
        end
    end

    // ------------------------------------------------
    // Output byte selection
    //
    // 0: output_0 low byte
    // 1: output_0 high byte
    // 2: output_1 low byte
    // 3: output_1 high byte
    // 4: output_2 low byte
    // 5: output_2 high byte
    // 6: output_3 low byte
    // 7: output_3 high byte
    // ------------------------------------------------

    reg [7:0] selected_byte;

    always @* begin
        case (output_count)
            3'd0: selected_byte = output_0_ext[7:0];
            3'd1: selected_byte = output_0_ext[15:8];
            3'd2: selected_byte = output_1_ext[7:0];
            3'd3: selected_byte = output_1_ext[15:8];
            3'd4: selected_byte = output_2_ext[7:0];
            3'd5: selected_byte = output_2_ext[15:8];
            3'd6: selected_byte = output_3_ext[7:0];
            3'd7: selected_byte = output_3_ext[15:8];
            default: selected_byte = 8'h00;
        endcase
    end

    assign uo_out =
        (ena && rst_n && state == ST_OUTPUT)
        ? selected_byte : 8'h00;

endmodule
