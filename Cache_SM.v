// ============================================================================
// Cache Security Monitor
// Target: PicoRV32 + Nexys 4 FPGA
//
// Monitors:
//   - Cache misses
//   - Cache evictions
//   - Memory bursts
//   - CPU/cache stall cycles
//   - Repeated cache-set conflicts
//
// Security Modes:
//   00 = NORMAL
//   01 = ALERT
//   10 = HARDENED
//   11 = Secondary Storage

// Hardened mode can request:
//   - Way partitioning
//   - Randomized replacement
// ============================================================================

module cache_security_monitor #(
    parameter COUNTER_WIDTH = 16,
    parameter SET_BITS      = 6,

    // Default thresholds
    parameter MISS_THRESHOLD_DEFAULT     = 16'd100,
    parameter EVICT_THRESHOLD_DEFAULT    = 16'd80,
    parameter BURST_THRESHOLD_DEFAULT    = 16'd50,
    parameter STALL_THRESHOLD_DEFAULT    = 16'd200,
    parameter CONFLICT_THRESHOLD_DEFAULT = 16'd32,

    // Observation window
    parameter WINDOW_CYCLES = 16'd4096
)(
    input wire clk,
    input wire resetn,

    // ------------------------------------------------------------
    // Cache / processor event inputs
    // ------------------------------------------------------------

    input wire cache_access,
    input wire cache_miss,
    input wire cache_evict,

    // High for a memory transaction/burst event
    input wire mem_burst,

    // High whenever processor waits for memory/cache
    input wire stall,

    // Cache set being accessed
    input wire [SET_BITS-1:0] cache_set,

    // ------------------------------------------------------------
    // Programmable thresholds
    // ------------------------------------------------------------

    input wire [COUNTER_WIDTH-1:0] miss_threshold,
    input wire [COUNTER_WIDTH-1:0] evict_threshold,
    input wire [COUNTER_WIDTH-1:0] burst_threshold,
    input wire [COUNTER_WIDTH-1:0] stall_threshold,
    input wire [COUNTER_WIDTH-1:0] conflict_threshold,

    // ------------------------------------------------------------
    // Security outputs
    // ------------------------------------------------------------

    output reg [1:0] security_mode,

    output wire normal_mode,
    output wire alert_mode,
    output wire hardened_mode,

    // Cache hardening controls
    output reg enable_way_partition,
    output reg enable_random_replacement,

    // Debug/performance counters
    output reg [COUNTER_WIDTH-1:0] miss_count,
    output reg [COUNTER_WIDTH-1:0] eviction_count,
    output reg [COUNTER_WIDTH-1:0] burst_count,
    output reg [COUNTER_WIDTH-1:0] stall_count,
    output reg [COUNTER_WIDTH-1:0] conflict_count
);


// ============================================================================
// Security mode definitions
// ============================================================================

localparam MODE_NORMAL   = 2'b00;
localparam MODE_ALERT    = 2'b01;
localparam MODE_HARDENED = 2'b10;


// ============================================================================
// Mode outputs
// ============================================================================

assign normal_mode   = (security_mode == MODE_NORMAL);
assign alert_mode    = (security_mode == MODE_ALERT);
assign hardened_mode = (security_mode == MODE_HARDENED);


// ============================================================================
// Observation window counter
// ============================================================================

reg [COUNTER_WIDTH-1:0] window_counter;


// ============================================================================
// Conflict detection
//
// Simple first implementation:
// If consecutive misses repeatedly target the same cache set,
// increment conflict counter.
//
// Later this can be replaced with per-set conflict counters.
// ============================================================================

reg [SET_BITS-1:0] previous_miss_set;
reg previous_miss_valid;


// ============================================================================
// Threshold detection
// ============================================================================

wire miss_alert;
wire eviction_alert;
wire burst_alert;
wire stall_alert;
wire conflict_alert;


assign miss_alert =
        (miss_count >= miss_threshold);

assign eviction_alert =
        (eviction_count >= evict_threshold);

assign burst_alert =
        (burst_count >= burst_threshold);

assign stall_alert =
        (stall_count >= stall_threshold);

assign conflict_alert =
        (conflict_count >= conflict_threshold);


// ============================================================================
// Threat score
//
// Multiple simultaneous abnormal behaviors indicate stronger evidence
// of cache interference.
// ============================================================================

wire [2:0] threat_score;

assign threat_score =
          miss_alert
        + eviction_alert
        + burst_alert
        + stall_alert
        + conflict_alert;


// ============================================================================
// Event Counters
// ============================================================================

always @(posedge clk) begin

    if (!resetn) begin

        miss_count      <= 0;
        eviction_count  <= 0;
        burst_count     <= 0;
        stall_count     <= 0;
        conflict_count  <= 0;

        window_counter  <= 0;

        previous_miss_set   <= 0;
        previous_miss_valid <= 0;

    end

    else begin

        // --------------------------------------------------------
        // Observation window
        // --------------------------------------------------------

        if (window_counter >= WINDOW_CYCLES - 1) begin

            window_counter <= 0;

            miss_count      <= 0;
            eviction_count  <= 0;
            burst_count     <= 0;
            stall_count     <= 0;
            conflict_count  <= 0;

            previous_miss_valid <= 0;

        end

        else begin

            window_counter <= window_counter + 1'b1;


            // ----------------------------------------------------
            // Cache miss counter
            // ----------------------------------------------------

            if (cache_miss)
                miss_count <= miss_count + 1'b1;


            // ----------------------------------------------------
            // Eviction counter
            // ----------------------------------------------------

            if (cache_evict)
                eviction_count <= eviction_count + 1'b1;


            // ----------------------------------------------------
            // Memory burst counter
            // ----------------------------------------------------

            if (mem_burst)
                burst_count <= burst_count + 1'b1;


            // ----------------------------------------------------
            // Stall-cycle counter
            // ----------------------------------------------------

            if (stall)
                stall_count <= stall_count + 1'b1;


            // ----------------------------------------------------
            // Repeated conflict detector
            //
            // Repeated misses to the same cache set are treated
            // as potential cache contention.
            // ----------------------------------------------------

            if (cache_miss) begin

                if (previous_miss_valid &&
                    (cache_set == previous_miss_set)) begin

                    conflict_count <= conflict_count + 1'b1;

                end

                previous_miss_set <= cache_set;
                previous_miss_valid <= 1'b1;

            end

        end

    end

end


// ============================================================================
// Security State Machine
// ============================================================================

always @(posedge clk) begin

    if (!resetn) begin

        security_mode <= MODE_NORMAL;

    end

    else begin

        case (security_mode)

            // ====================================================
            // NORMAL MODE
            // ====================================================

            MODE_NORMAL: begin

                // One abnormal metric -> ALERT
                if (threat_score >= 1)
                    security_mode <= MODE_ALERT;

            end


            // ====================================================
            // ALERT MODE
            // ====================================================

            MODE_ALERT: begin

                // Multiple abnormal metrics strongly suggest
                // interference.
                if (threat_score >= 3)
                    security_mode <= MODE_HARDENED;

                // Return to normal at end of clean window
                else if ((window_counter == WINDOW_CYCLES - 1) &&
                         (threat_score == 0))
                    security_mode <= MODE_NORMAL;

            end


            // ====================================================
            // HARDENED MODE
            // ====================================================

            MODE_HARDENED: begin

                // Stay hardened during current observation window.
                //
                // At the end of a clean window, downgrade to ALERT.
                if ((window_counter == WINDOW_CYCLES - 1) &&
                    (threat_score == 0))
                    security_mode <= MODE_ALERT;

            end


            default:
                security_mode <= MODE_NORMAL;

        endcase

    end

end


// ============================================================================
// Cache Policy Controller
// ============================================================================

always @(*) begin

    // Defaults
    enable_way_partition      = 1'b0;
    enable_random_replacement = 1'b0;


    case (security_mode)

        MODE_NORMAL: begin

            enable_way_partition      = 1'b0;
            enable_random_replacement = 1'b0;

        end


        MODE_ALERT: begin

            // Begin randomizing replacement behavior.
            enable_way_partition      = 1'b0;
            enable_random_replacement = 1'b1;

        end


        MODE_HARDENED: begin

            // Strongest protection
            enable_way_partition      = 1'b1;
            enable_random_replacement = 1'b1;

        end


        default: begin

            enable_way_partition      = 1'b0;
            enable_random_replacement = 1'b0;

        end

    endcase

end


endmodule
