module edgeDetector (
    input logic i_rx ,
    input logic clk ,
    input logic rst ,
    output logic posedge_rx ,
    output logic negedge_rx ,
    output logic edge_rx ,
    output logic rx_Delayed
);
    logic rx_meta ;
    logic rx_previous ;
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            rx_meta <= 1'b1;
            rx_Delayed <= 1'b1;
            rx_previous <= 1'b1;
        end
        else begin
            rx_meta <= i_rx;
            rx_Delayed <= rx_meta;
            rx_previous <= rx_Delayed;
        end
    end
    always_comb begin
        posedge_rx = rx_Delayed & (~rx_previous) ;
        negedge_rx = ~rx_Delayed & rx_previous ;
        edge_rx = rx_Delayed ^ rx_previous ;
    end
endmodule


module sampler (
    input logic i_rx ,clk,rst ,
    output logic [10:0] o_sampler,
    output logic ready ,
    output logic busy 
);
    logic rx_delayed ;
    logic rx_posedge ;
    logic rx_negedge ;
    logic rx_edge;
    logic [3:0] count ;

    edgeDetector u_edge_detector (
        .i_rx(i_rx),
        .clk(clk),
        .rst(rst),
        .posedge_rx(rx_posedge),
        .negedge_rx(rx_negedge),
        .edge_rx(rx_edge),
        .rx_Delayed(rx_delayed)
    );
    always_ff @( posedge clk or negedge rst ) begin 
        if(!rst) begin
            o_sampler <= 11'b0 ;
            ready <= 0;
            busy <= 1'b0;
            count <= 0;
        end
        else begin
            ready <= 0;
            if (rx_negedge && !busy) begin
                busy <= 1 ;
                count <= 1;
                o_sampler <= 11'b0;
                o_sampler[0] <= rx_delayed;
            end
            else if (busy == 1) begin
                o_sampler[count] <= rx_delayed;
                if (count == 4'd10) begin
                    busy <= 0;
                    ready <= 1;
                    count <= 0;
                end
                else begin
                    count <= count + 1;
                end
            end
        end
    end
endmodule

module errorCheckerModule (
    input logic i_rx ,
    input logic clk ,
    input logic rst ,
    input logic parity_enable , // fsm
    input logic parity_type , // fsm
    output logic [7:0] Data ,
    output logic valid ,
    output logic busy ,
    output logic o_parity_err ,
    output logic o_frame_err
);
    logic [10:0] Register ;
    logic parityBit ;
    logic Sampler_ready ;

    sampler u_sampler(
        .i_rx(i_rx),
        .clk(clk),
        .rst(rst),
        .o_sampler(Register),
        .ready(Sampler_ready),
        .busy(busy)
    );
    always_comb begin 
        Data = Register[8:1];
        valid = Sampler_ready;
        parityBit = (^Data) ^ parity_type;
        o_parity_err = 1'b0;
        o_frame_err = 1'b0;

        if (Sampler_ready) begin
            if (parity_enable) begin
                if (Register[9] != parityBit)
                    o_parity_err = 1'b1;

                if (Register[10] != 1'b1)
                    o_frame_err = 1'b1;
            end
            else begin
                if (Register[9] != 1'b1)
                    o_frame_err = 1'b1;
            end
        end
    end
    
endmodule


module uart_rx_fsm (
    input logic i_clk ,
    input logic i_rst_n ,
    input logic i_start ,
    input logic i_par_en ,

    output logic o_busy ,
    output logic sample_data ,
    output logic sample_parity ,
    output logic sample_stop ,
    output logic [2:0] count
);

    typedef enum logic [1:0] {
        IDLE ,
        DATA ,
        PARITY ,
        STOP
    } state_t;

    state_t state;
    state_t next_state;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state <= IDLE;
            count <= 3'b000;
        end
        else begin
            state <= next_state;

            if (state == DATA) begin
                if (count == 3'd7)
                    count <= 3'b000;
                else
                    count <= count + 1'b1;
            end
            else begin
                count <= 3'b000;
            end
        end
    end

    always_comb begin
        next_state = state;

        o_busy = 1'b0;
        sample_data = 1'b0;
        sample_parity = 1'b0;
        sample_stop = 1'b0;

        unique case (state)

            IDLE: begin
                if (i_start)
                    next_state = DATA;
            end

            DATA: begin
                o_busy = 1'b1;
                sample_data = 1'b1;

                if (count == 3'd7) begin
                    if (i_par_en)
                        next_state = PARITY;
                    else
                        next_state = STOP;
                end
            end

            PARITY: begin
                o_busy = 1'b1;
                sample_parity = 1'b1;
                next_state = STOP;
            end

            STOP: begin
                o_busy = 1'b1;
                sample_stop = 1'b1;
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end

        endcase
    end

endmodule


module uart_rx #(parameter DATA_W=8) (
    input logic i_rx,
    input logic i_clk,
    input logic i_rst_n,
    input logic i_par_en,
    input logic i_par_odd,
    output logic [DATA_W-1:0] o_data,
    output logic o_valid,
    output logic o_busy,
    output logic o_parity_err,
    output logic o_frame_err
);

    errorCheckerModule u_error_checker (
        .i_rx(i_rx),
        .clk(i_clk),
        .rst(i_rst_n),
        .parity_enable(i_par_en),
        .parity_type(i_par_odd),
        .Data(o_data),
        .valid(o_valid),
        .busy(o_busy),
        .o_parity_err(o_parity_err),
        .o_frame_err(o_frame_err)
    );

endmodule

`default_nettype wire
