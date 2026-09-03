module FULLADDER (
    input A,
    input B,
    input C,
    output reg R
);

always_comb begin
    R = A + B + C;
end

endmodule


module uart_serializer (
    input clk,
    input rst,
    input mode,
    input start,
    input [10:0] registerIn,
    output reg [10:0] register,
    output reg Dout,
    output reg done
);

    reg [3:0] count;

    always_ff @(posedge clk or negedge rst) begin

        if (!rst) begin
            done <= 1'b1;
            Dout <= 1'b1;
            register <= 11'b0;
            count <= 4'b0;
        end

        else begin

            if (done == 1 && start == 1) begin
                register <= registerIn;
                done <= 1'b0;
                count <= 4'b0;
                Dout <= 1'b1;
            end

            else if (done == 0 && mode == 0) begin

                Dout <= register[0];

                register[0] <= register[1];
                register[1] <= register[2];
                register[2] <= register[3];
                register[3] <= register[4];
                register[4] <= register[5];
                register[5] <= register[6];
                register[6] <= register[7];
                register[7] <= register[8];
                register[8] <= register[9];
                register[9] <= register[10];

                if (count == 4'd10) begin
                    done <= 1'b1;
                    Dout <= 1'b1;
                end

                else begin
                    count <= count + 1'b1;
                end

            end

            else if (done == 0 && mode == 1) begin

                Dout <= register[0];

                register[0] <= register[1];
                register[1] <= register[2];
                register[2] <= register[3];
                register[3] <= register[4];
                register[4] <= register[5];
                register[5] <= register[6];
                register[6] <= register[7];
                register[7] <= register[8];
                register[8] <= register[9];

                if (count == 4'd9) begin
                    done <= 1'b1;
                    Dout <= 1'b1;
                end

                else begin
                    count <= count + 1'b1;
                end

            end

        end

    end

endmodule





module uart_paritycalc (
    input [7:0] parallel_register,
    input parity_type,
    output reg parity_bit
);

    logic s1;
    logic s2;
    logic s3;
    logic final_sum;

    FULLADDER FA1 (
        .A(parallel_register[0]),
        .B(parallel_register[1]),
        .C(parallel_register[2]),
        .R(s1)
    );

    FULLADDER FA2 (
        .A(parallel_register[3]),
        .B(parallel_register[4]),
        .C(parallel_register[5]),
        .R(s2)
    );

    FULLADDER FA3 (
        .A(s1),
        .B(s2),
        .C(parallel_register[6]),
        .R(s3)
    );

    FULLADDER FA4 (
        .A(s3),
        .B(parallel_register[7]),
        .C(1'b0),
        .R(final_sum)
    );

    always_comb begin

        if (parity_type == 1'b0) begin
            parity_bit = final_sum;
        end

        else begin
            parity_bit = ~final_sum;
        end

    end

endmodule


module uart_fsm (
    input clk,
    input rst,

    input mode,
    input parity_type,

    input buffer_ready,
    input [7:0] buffer_data,

    input serializer_done,

    output reg buffer_read_en,
    output busy,
    output reg serializer_start,
    output reg [10:0] serializer_data
);

    reg [2:0] state;
    reg [7:0] data_reg;

    logic parity_bit;

    uart_paritycalc parity (
        .parallel_register(data_reg),
        .parity_type(parity_type),
        .parity_bit(parity_bit)
    );

    typedef enum logic [2:0] {
        IDLE     = 3'b000,
        READ     = 3'b001,
        LOAD     = 3'b010,
        START    = 3'b011,
        WAIT_START = 3'b100,
        WAIT_DONE  = 3'b101
    } state_t;

    assign busy = (state != IDLE);

    always_ff @(posedge clk or negedge rst) begin

        if (!rst) begin

            state <= IDLE;
            data_reg <= 8'b0;
            buffer_read_en <= 1'b0;
            serializer_start <= 1'b0;
            serializer_data <= 11'b0;

        end

        else begin

            buffer_read_en <= 1'b0;
            case (state)

                IDLE: begin
                    serializer_start <= 1'b0;
                    if (buffer_ready)
                        state <= READ;
                end
                READ: begin
                    serializer_start <= 1'b0;

                    buffer_read_en <= 1'b1;
                    data_reg <= buffer_data;

                    state <= LOAD;

                end
                LOAD: begin

                    serializer_start <= 1'b0;

                    serializer_data[0] <= 1'b0;
                    serializer_data[8:1] <= data_reg;

                    if (mode == 1'b0) begin
                        serializer_data[9] <= parity_bit;
                        serializer_data[10] <= 1'b1;
                    end

                    else begin
                        serializer_data[9] <= 1'b1;
                        serializer_data[10] <= 1'b0;
                    end

                    state <= START;

                end
                START: begin

                    serializer_start <= 1'b1;

                    state <= WAIT_START;

                end


                WAIT_START: begin

                    serializer_start <= 1'b1;

                    if (!serializer_done)
                        state <= WAIT_DONE;

                end


                WAIT_DONE: begin

                    serializer_start <= 1'b0;

                    if (serializer_done)
                        state <= IDLE;

                end


                default: begin

                    state <= IDLE;
                    buffer_read_en <= 1'b0;
                    serializer_start <= 1'b0;

                end

            endcase

        end

    end

endmodule


module uart_tx #(parameter DATA_W=8) (
    input [DATA_W-1:0] i_data,
    input i_valid,
    input i_clk,
    input i_rst_n,
    input i_par_en,
    input i_par_odd,

    output o_tx,
    output o_busy
);

    logic serializer_start;
    logic serializer_done;
    logic mode;
    logic buffer_read_en;

    logic [10:0] serializer_data;

    assign mode = ~i_par_en;


    uart_fsm fsm (
        .clk(i_clk),
        .rst(i_rst_n),
        .mode(mode),
        .parity_type(i_par_odd),
        .buffer_ready(i_valid),
        .buffer_data(i_data),
        .serializer_done(serializer_done),
        .buffer_read_en(buffer_read_en),
        .busy(o_busy),
        .serializer_start(serializer_start),
        .serializer_data(serializer_data)
    );


    uart_serializer serializer (
        .clk(i_clk),
        .rst(i_rst_n),
        .mode(mode),
        .start(serializer_start),
        .registerIn(serializer_data),
        .register(),
        .Dout(o_tx),
        .done(serializer_done)
    );

endmodule
