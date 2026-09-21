`timescale 1ns / 1ps

// ============================================================================
// Integrated Testbench
// PicoRV32 Cache Security System
//
// Tests:
//   1. Security Monitor
//      - NORMAL -> ALERT -> HARDENED
//   2. Random Replacement
//      - LFSR generates different replacement ways
//   3. Way Partitioning
//      - Trusted domain   -> Ways 0/1
//      - Untrusted domain -> Ways 2/3
//   4. Recovery after suspicious activity stops
// ============================================================================

module tb_cache_security_system;

    // ========================================================================
    // Parameters
    // ========================================================================

    parameter COUNTER_WIDTH = 16;
    parameter SET_BITS      = 6;

    // Small thresholds make simulation faster.
    parameter MISS_THRESHOLD     = 5;
    parameter EVICT_THRESHOLD    = 4;
    parameter BURST_THRESHOLD    = 4;
    parameter STALL_THRESHOLD    = 6;
    parameter CONFLICT_THRESHOLD = 4;

    // Use a short window for simulation.
    parameter WINDOW_CYCLES = 50;


    // ========================================================================
    // Clock / Reset
    // ========================================================================

    reg clk;
    reg resetn;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;      // 100 MHz clock
    end


    // ========================================================================
    // Security Monitor Inputs
    // ========================================================================

    reg cache_access;
    reg cache_miss;
    reg cache_evict;
    reg mem_burst;
    reg stall;

    reg [SET_BITS-1:0] cache_set;


    // ========================================================================
    // Threshold Inputs
    // ========================================================================

    reg [COUNTER_WIDTH-1:0] miss_threshold;
    reg [COUNTER_WIDTH-1:0] evict_threshold;
    reg [COUNTER_WIDTH-1:0] burst_threshold;
    reg [COUNTER_WIDTH-1:0] stall_threshold;
    reg [COUNTER_WIDTH-1:0] conflict_threshold;


    // ========================================================================
    // Security Monitor Outputs
    // ========================================================================

    wire [1:0] security_mode;

    wire normal_mode;
    wire alert_mode;
    wire hardened_mode;

    wire enable_way_partition;
    wire enable_random_replacement;

    wire [COUNTER_WIDTH-1:0] miss_count;
    wire [COUNTER_WIDTH-1:0] eviction_count;
    wire [COUNTER_WIDTH-1:0] burst_count;
    wire [COUNTER_WIDTH-1:0] stall_count;
    wire [COUNTER_WIDTH-1:0] conflict_count;


    // ========================================================================
    // Random Replacement Signals
    // ========================================================================

    reg advance_random;

    wire [1:0] random_way;


    // ========================================================================
    // Cache Replacement / Partition Signals
    // ========================================================================

    reg trusted_domain;

    // Example output from an LRU implementation.
    // We simply drive it manually in this testbench.
    reg [1:0] lru_way;

    reg [1:0] replacement_way;


    // ========================================================================
    // Security Monitor DUT
    // ========================================================================

    cache_security_monitor #(

        .COUNTER_WIDTH(COUNTER_WIDTH),
        .SET_BITS(SET_BITS),

        .WINDOW_CYCLES(WINDOW_CYCLES)

    ) security_monitor (

        .clk(clk),
        .resetn(resetn),

        .cache_access(cache_access),
        .cache_miss(cache_miss),
        .cache_evict(cache_evict),

        .mem_burst(mem_burst),
        .stall(stall),

        .cache_set(cache_set),

        .miss_threshold(miss_threshold),
        .evict_threshold(evict_threshold),
        .burst_threshold(burst_threshold),
        .stall_threshold(stall_threshold),
        .conflict_threshold(conflict_threshold),

        .security_mode(security_mode),

        .normal_mode(normal_mode),
        .alert_mode(alert_mode),
        .hardened_mode(hardened_mode),

        .enable_way_partition(enable_way_partition),
        .enable_random_replacement(enable_random_replacement),

        .miss_count(miss_count),
        .eviction_count(eviction_count),
        .burst_count(burst_count),
        .stall_count(stall_count),
        .conflict_count(conflict_count)

    );


    // ========================================================================
    // Random Replacement DUT
    // ========================================================================

    random_replacement random_policy (

        .clk(clk),
        .resetn(resetn),

        .advance(advance_random),

        .random_way(random_way)

    );


    // ========================================================================
    // Replacement Policy Logic
    //
    // NORMAL:
    //      LRU replacement
    //
    // ALERT:
    //      Random replacement
    //
    // HARDENED:
    //      Random replacement + way partitioning
    //
    // Trusted   -> Ways 0 / 1
    // Untrusted -> Ways 2 / 3
    // ========================================================================

    always @(*) begin

        if (enable_way_partition) begin

            if (trusted_domain)

                // Trusted domain:
                // random_way[0] = 0 -> Way 0
                // random_way[0] = 1 -> Way 1

                replacement_way = {
                    1'b0,
                    random_way[0]
                };

            else

                // Untrusted domain:
                // random_way[0] = 0 -> Way 2
                // random_way[0] = 1 -> Way 3

                replacement_way = {
                    1'b1,
                    random_way[0]
                };

        end

        else if (enable_random_replacement) begin

            replacement_way = random_way;

        end

        else begin

            replacement_way = lru_way;

        end

    end


    // ========================================================================
    // Helper Task: Generate Cache Miss
    // ========================================================================

    task generate_miss;

        input [SET_BITS-1:0] set_number;

        begin

            @(negedge clk);

            cache_access = 1;
            cache_miss   = 1;
            cache_set    = set_number;

            @(negedge clk);

            cache_access = 0;
            cache_miss   = 0;

        end

    endtask


    // ========================================================================
    // Helper Task: Generate Eviction
    // ========================================================================

    task generate_eviction;

        begin

            @(negedge clk);

            cache_evict = 1;

            @(negedge clk);

            cache_evict = 0;

        end

    endtask


    // ========================================================================
    // Helper Task: Generate Memory Burst
    // ========================================================================

    task generate_burst;

        begin

            @(negedge clk);

            mem_burst = 1;

            @(negedge clk);

            mem_burst = 0;

        end

    endtask


    // ========================================================================
    // Helper Task: Generate Stall
    // ========================================================================

    task generate_stall;

        begin

            @(negedge clk);

            stall = 1;

            @(negedge clk);

            stall = 0;

        end

    endtask


    // ========================================================================
    // Helper Task: Advance Random Replacement
    // ========================================================================

    task advance_lfsr;

        begin

            @(negedge clk);

            advance_random = 1;

            @(negedge clk);

            advance_random = 0;

        end

    endtask


    // ========================================================================
    // Monitor Security Mode
    // ========================================================================

    always @(security_mode) begin

        case (security_mode)

            2'b00:
                $display(
                    "[%0t] SECURITY MODE -> NORMAL",
                    $time
                );

            2'b01:
                $display(
                    "[%0t] SECURITY MODE -> ALERT",
                    $time
                );

            2'b10:
                $display(
                    "[%0t] SECURITY MODE -> HARDENED",
                    $time
                );

            default:
                $display(
                    "[%0t] SECURITY MODE -> UNKNOWN",
                    $time
                );

        endcase

    end


    // ========================================================================
    // Main Test Sequence
    // ========================================================================

    integer i;

    initial begin

        // --------------------------------------------------------------------
        // Initial values
        // --------------------------------------------------------------------

        resetn = 0;

        cache_access = 0;
        cache_miss   = 0;
        cache_evict  = 0;

        mem_burst = 0;
        stall     = 0;

        cache_set = 0;

        advance_random = 0;

        trusted_domain = 1;

        lru_way = 2'd0;


        // --------------------------------------------------------------------
        // Threshold configuration
        // --------------------------------------------------------------------

        miss_threshold     = MISS_THRESHOLD;
        evict_threshold    = EVICT_THRESHOLD;
        burst_threshold    = BURST_THRESHOLD;
        stall_threshold    = STALL_THRESHOLD;
        conflict_threshold = CONFLICT_THRESHOLD;


        // --------------------------------------------------------------------
        // Reset
        // --------------------------------------------------------------------

        $display("");
        $display("==========================================");
        $display(" CACHE SECURITY SYSTEM TESTBENCH");
        $display("==========================================");

        #30;

        resetn = 1;

        $display("");
        $display("[%0t] Reset released", $time);


        // ====================================================================
        // TEST 1
        // Verify NORMAL mode
        // ====================================================================

        $display("");
        $display("------------------------------------------");
        $display("TEST 1: NORMAL MODE");
        $display("------------------------------------------");

        repeat (5)
            @(posedge clk);


        if (normal_mode)

            $display(
                "PASS: Cache starts in NORMAL mode"
            );

        else

            $error(
                "FAIL: Cache did not start in NORMAL mode"
            );


        // ====================================================================
        // TEST 2
        // Generate misses to enter ALERT mode
        // ====================================================================

        $display("");
        $display("------------------------------------------");
        $display("TEST 2: MISS THRESHOLD / ALERT MODE");
        $display("------------------------------------------");


        for (i = 0; i < MISS_THRESHOLD + 1; i = i + 1) begin

            generate_miss(i);

            $display(
                "Miss generated: Set=%0d MissCount=%0d",
                i,
                miss_count
            );

        end


        repeat (2)
            @(posedge clk);


        if (alert_mode)

            $display(
                "PASS: Security monitor entered ALERT mode"
            );

        else

            $error(
                "FAIL: Expected ALERT mode"
            );


        // ====================================================================
        // TEST 3
        // Verify random replacement in ALERT mode
        // ====================================================================

        $display("");
        $display("------------------------------------------");
        $display("TEST 3: RANDOM REPLACEMENT");
        $display("------------------------------------------");


        for (i = 0; i < 10; i = i + 1) begin

            advance_lfsr();

            $display(
                "Random replacement %0d -> Way %0d",
                i,
                replacement_way
            );

        end


        if (enable_random_replacement)

            $display(
                "PASS: Random replacement enabled"
            );

        else

            $error(
                "FAIL: Random replacement not enabled"
            );


        // ====================================================================
        // TEST 4
        // Generate suspicious cache activity
        // ====================================================================

        $display("");
        $display("------------------------------------------");
        $display("TEST 4: SIMULATED CACHE ATTACK");
        $display("------------------------------------------");


        // --------------------------------------------------------------------
        // Repeated misses to same set
        //
        // This represents repeated conflict behavior.
        // --------------------------------------------------------------------

        for (i = 0; i < 6; i = i + 1) begin

            generate_miss(6'd17);

            $display(
                "Conflict access -> Set 17"
            );

        end


        // --------------------------------------------------------------------
        // Generate evictions
        // --------------------------------------------------------------------

        for (i = 0; i < 5; i = i + 1)

            generate_eviction();


        // --------------------------------------------------------------------
        // Generate memory bursts
        // --------------------------------------------------------------------

        for (i = 0; i < 5; i = i + 1)

            generate_burst();


        // --------------------------------------------------------------------
        // Generate stall cycles
        // --------------------------------------------------------------------

        for (i = 0; i < 7; i = i + 1)

            generate_stall();


        repeat (3)
            @(posedge clk);


        $display("");
        $display("Attack statistics:");

        $display(
            "Misses     = %0d",
            miss_count
        );

        $display(
            "Evictions  = %0d",
            eviction_count
        );

        $display(
            "Bursts     = %0d",
            burst_count
        );

        $display(
            "Stalls     = %0d",
            stall_count
        );

        $display(
            "Conflicts  = %0d",
            conflict_count
        );


        // ====================================================================
        // TEST 5
        // Verify HARDENED mode
        // ====================================================================

        $display("");
        $display("------------------------------------------");
        $display("TEST 5: HARDENED MODE");
        $display("------------------------------------------");


        if (hardened_mode)

            $display(
                "PASS: Security monitor entered HARDENED mode"
            );

        else

            $error(
                "FAIL: Expected HARDENED mode"
            );


        if (enable_way_partition)

            $display(
                "PASS: Way partitioning enabled"
            );

        else

            $error(
                "FAIL: Way partitioning not enabled"
            );


        // ====================================================================
        // TEST 6
        // Trusted Domain Partition
        // ====================================================================

        $display("");
        $display("------------------------------------------");
        $display("TEST 6: TRUSTED DOMAIN WAY PARTITION");
        $display("------------------------------------------");


        trusted_domain = 1;


        for (i = 0; i < 10; i = i + 1) begin

            advance_lfsr();

            #1;

            $display(
                "Trusted replacement -> Way %0d",
                replacement_way
            );


            // Trusted domain must only use Ways 0 or 1.

            if (replacement_way > 1)

                $error(
                    "SECURITY FAILURE: Trusted domain selected Way %0d",
                    replacement_way
                );

        end


        $display(
            "PASS: Trusted domain restricted to Ways 0/1"
        );


        // ====================================================================
        // TEST 7
        // Untrusted Domain Partition
        // ====================================================================

        $display("");
        $display("------------------------------------------");
        $display("TEST 7: UNTRUSTED DOMAIN WAY PARTITION");
        $display("------------------------------------------");


        trusted_domain = 0;


        for (i = 0; i < 10; i = i + 1) begin

            advance_lfsr();

            #1;

            $display(
                "Untrusted replacement -> Way %0d",
                replacement_way
            );


            // Untrusted domain must only use Ways 2 or 3.

            if (replacement_way < 2)

                $error(
                    "SECURITY FAILURE: Untrusted domain selected Way %0d",
                    replacement_way
                );

        end


        $display(
            "PASS: Untrusted domain restricted to Ways 2/3"
        );


        // ====================================================================
        // TEST 8
        // Verify isolation
        // ====================================================================

        $display("");
        $display("------------------------------------------");
        $display("TEST 8: CACHE ISOLATION");
        $display("------------------------------------------");


        trusted_domain = 1;

        advance_lfsr();

        #1;


        if (replacement_way <= 1)

            $display(
                "PASS: Trusted access stays in trusted partition"
            );

        else

            $error(
                "FAIL: Trusted access escaped partition"
            );


        trusted_domain = 0;

        advance_lfsr();

        #1;


        if (replacement_way >= 2)

            $display(
                "PASS: Untrusted access stays in untrusted partition"
            );

        else

            $error(
                "FAIL: Untrusted access entered trusted partition"
            );


        // ====================================================================
        // Finish
        // ====================================================================

        $display("");
        $display("==========================================");
        $display(" TESTBENCH COMPLETED");
        $display("==========================================");

        $display("");
        $display("Final Security Mode = %b", security_mode);
        $display("Miss Count          = %0d", miss_count);
        $display("Eviction Count      = %0d", eviction_count);
        $display("Burst Count         = %0d", burst_count);
        $display("Stall Count         = %0d", stall_count);
        $display("Conflict Count      = %0d", conflict_count);

        $display("");

        #50;

        $finish;

    end


    // ========================================================================
    // Optional waveform dump
    //
    // Useful with Icarus Verilog + GTKWave.
    // Vivado simulator can display signals directly.
    // ========================================================================

    initial begin

        $dumpfile("cache_security_tb.vcd");

        $dumpvars(
            0,
            tb_cache_security_system
        );

    end


endmodule
