library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Sequential ALU controlled by a 4-bit switch bus and a confirm button.
-- Flow: select operation -> enter operand A -> enter operand B -> execute.
-- While waiting for input, the LEDs play an idle "chaser" animation.
entity ULA_SD is
    port (
        clk          : in  std_logic;
        sel          : in  std_logic_vector(3 downto 0);  -- switches: operation code, then operand A, then operand B
        reset        : in  std_logic;                     -- asynchronous reset
        confirm      : in  std_logic;                     -- button that advances the FSM (goes through a debouncer)
        resul        : out std_logic_vector(3 downto 0);  -- 4-bit result (LEDs)
        led_zero     : out std_logic;                     -- zero flag
        led_negative : out std_logic;                     -- negative flag
        led_overflow : out std_logic;                     -- overflow flag
        led_carry    : out std_logic                      -- carry flag
    );
end ULA_SD;

architecture comportamento of ULA_SD is
    -- Debouncer: produces a clean single-cycle pulse per button press
    component debounce_ula is
        port(
            clk        : in  std_logic;
            confirm    : in  std_logic;
            confirm_db : out std_logic;
            pulso      : out std_logic
        );
    end component;

    -- Idle (waiting) animation variables ------------------------------------------------------- 
    -- Idle animation FSM: 8 steps, each one lights a different pair of LEDs
    type tipo_estado_led is (animacao_1, animacao_2, animacao_3, animacao_4, animacao_5, animacao_6, animacao_7, animacao_8);
    signal estado_led_at : tipo_estado_led := animacao_1;
    -- Delay counter for each animation step (12.5M cycles per step; the clock is presumably 50 MHz -> ~0.25 s)
    signal balde_load    : integer range 0 to 12500000 := 0;
    ---------------------------------------------------------------------------------------------

    -- Main FSM: waits for operation, operand A, operand B, then executes
    type tipo_estado is (espera_sel, espera_a, espera_b, exe_operacao);
    signal estado_atual  : tipo_estado := espera_sel;
    signal vetor_sel     : std_logic_vector(2 downto 0);  -- latched operation code
    signal vetor_a       : std_logic_vector(3 downto 0);  -- latched operand A
    signal vetor_b       : std_logic_vector(3 downto 0);  -- latched operand B
    signal confirm_pulso : std_logic;                     -- debounced one-cycle pulse from the confirm button
    signal balde_cont    : std_logic_vector(3 downto 0);  -- running value used by the counting operation ("000")
    signal ref_cont      : integer range 0 to 3 := 0;     -- flag/counter: 0 = counter not yet initialised
    signal vetor_ref     : std_logic_vector(4 downto 0);  -- 5-bit intermediate result (bit 4 = carry/extra bit)
begin

    u_debounce: debounce_ula port map(
        clk        => clk,
        confirm    => confirm,
        confirm_db => open,           -- debounced level output is unused
        pulso      => confirm_pulso
    );

    -- Single process: reset is asynchronous, everything else is synchronous to clk
    process (clk, reset)
    begin
        if reset = '1' then
            -- Put everything back to the initial state
            estado_atual  <= espera_sel;
            vetor_sel     <= (others => '0');
            vetor_a       <= (others => '0');
            vetor_b       <= (others => '0');
            resul         <= (others => '0');
            estado_led_at <= animacao_1;
            balde_load    <= 0;
            led_zero      <= '0';
            led_negative  <= '0';
            led_overflow  <= '0';
            led_carry     <= '0';
            balde_cont    <= (others => '0');
            ref_cont      <= 0;
            vetor_ref     <= (others => '0');
        elsif rising_edge(clk) then
            -- Idle animation: runs whenever the FSM is NOT executing an operation.
            -- Outputs are cleared first, then the current animation step sets its two LEDs
            -- (last assignment wins in VHDL).
            if not (estado_atual = exe_operacao) then
                led_zero     <= '0';
                led_negative <= '0';
                led_overflow <= '0';
                led_carry    <= '0';
                resul        <= (others => '0');
              
                -- Each step holds for 12.5M cycles, then moves to the next one (cyclic 1 -> 8 -> 1)
                case estado_led_at is
                    when animacao_1 =>
                        if balde_load < 12500000 then
                            balde_load   <= balde_load + 1;
                            led_zero     <= '1';
                            led_negative <= '1';
                        else
                            balde_load    <= 0;
                            estado_led_at <= animacao_2;
                        end if;
                    
                    when animacao_2 =>
                        if balde_load < 12500000 then
                            balde_load   <= balde_load + 1;
                            led_negative <= '1';
                            led_overflow <= '1';
                        else
                            balde_load    <= 0;
                            estado_led_at <= animacao_3;
                        end if;

                    when animacao_3 =>
                        if balde_load < 12500000 then
                            balde_load   <= balde_load + 1;
                            led_overflow <= '1';
                            led_carry    <= '1';
                        else
                            balde_load    <= 0;
                            estado_led_at <= animacao_4;
                        end if;

                    when animacao_4 =>
                        if balde_load < 12500000 then
                            balde_load <= balde_load + 1;
                            led_carry  <= '1';
                            resul(3)   <= '1';
                        else
                            balde_load    <= 0;
                            estado_led_at <= animacao_5;
                        end if;

                    when animacao_5 =>
                        if balde_load < 12500000 then
                            balde_load <= balde_load + 1;
                            resul(3)   <= '1';
                            resul(2)   <= '1';
                        else
                            balde_load    <= 0;
                            estado_led_at <= animacao_6;
                        end if;
                    
                    when animacao_6 =>
                        if balde_load < 12500000 then
                            balde_load <= balde_load + 1;
                            resul(2)   <= '1';
                            resul(1)   <= '1';
                        else
                            balde_load    <= 0;
                            estado_led_at <= animacao_7;
                        end if;

                    when animacao_7 =>
                        if balde_load < 12500000 then
                            balde_load <= balde_load + 1;
                            resul(1)   <= '1';
                            resul(0)   <= '1';
                        else
                            balde_load    <= 0;
                            estado_led_at <= animacao_8;
                        end if;

                    when animacao_8 =>
                        if balde_load < 12500000 then
                            balde_load <= balde_load + 1;
                            resul(0)   <= '1';
                            led_zero   <= '1';
                        else
                            balde_load    <= 0;
                            estado_led_at <= animacao_1;
                        end if;
                end case;
            end if;
            
            -- Main FSM
            case estado_atual is
                when espera_sel =>
                    -- Latch the operation code (only the 3 low switches are used)
                    if confirm_pulso = '1' then
                        vetor_sel    <= sel(2 downto 0);
                        estado_atual <= espera_a;
                    end if;

                when espera_a =>
                    -- Latch operand A
                    if confirm_pulso = '1' then
                        vetor_a      <= sel;
                        estado_atual <= espera_b;
                    end if;

                when espera_b =>
                    -- Latch operand B and start execution
                    if confirm_pulso = '1' then
                        vetor_b      <= sel;
                        estado_atual <= exe_operacao;
                    end if;

                when exe_operacao =>
                    -- Flags are cleared every cycle and re-set by the selected operation below
                    led_zero     <= '0';
                    led_negative <= '0';
                    led_overflow <= '0';
                    led_carry    <= '0';
                    vetor_ref    <= (others => '0');
                    
                    -- Operation codes:
                    -- 000 count A..B | 001 add | 010 subtract | 011 min | 100 max
                    -- 101 average    | 110 OR  | 111 AND
                    case vetor_sel is
                        when "000" => -- counts from vetor_a up to vetor_b
                            -- First pass (ref_cont = 0): initialise the counter with A and restart the animation
                            if ref_cont < 1 then
                                balde_cont    <= vetor_a;
                                ref_cont      <= ref_cont + 1;
                                balde_load    <= 0;
                                resul         <= vetor_a;
                                estado_led_at <= animacao_1;
                            -- Counting phase: while counter < B, show the counter and run a
                            -- reduced animation (one LED at a time) between increments
                            elsif (ref_cont >= 1) and (unsigned(balde_cont) < unsigned(vetor_b)) then
                                led_zero     <= '0';
                                led_negative <= '0';
                                led_overflow <= '0';
                                led_carry    <= '0';
                                resul        <= balde_cont;
                                
                                case estado_led_at is
                                    when animacao_1 =>
                                        if balde_load < 12500000 then
                                            balde_load <= balde_load + 1;
                                            led_zero   <= '1';
                                        else
                                            balde_load    <= 0;
                                            estado_led_at <= animacao_2;
                                        end if;
                            
                                    when animacao_2 =>
                                        if balde_load < 12500000 then
                                            balde_load   <= balde_load + 1;
                                            led_negative <= '1';
                                        else
                                            balde_load    <= 0;
                                            estado_led_at <= animacao_3;
                                        end if;

                                    when animacao_3 =>
                                        if balde_load < 12500000 then
                                            balde_load   <= balde_load + 1;
                                            led_overflow <= '1';
                                        else
                                            balde_load    <= 0;
                                            estado_led_at <= animacao_4;
                                        end if;

                                    when animacao_4 =>
                                        if balde_load < 12500000 then
                                            balde_load <= balde_load + 1;
                                            led_carry  <= '1';
                                        else
                                            balde_load    <= 0;
                                            estado_led_at <= animacao_5;
                                        end if;

                                    when animacao_5 =>
                                        -- Increment the counter exactly once (on the first cycle of this step),
                                        -- then just wait out the delay before restarting the animation
                                        if balde_load < 1 then
                                            balde_cont <= std_logic_vector(unsigned(balde_cont) + 1);
                                            balde_load <= balde_load + 1;
                                        elsif balde_load < 12500000 then
                                            balde_load <= balde_load + 1;
                                        else
                                            balde_load    <= 0;
                                            estado_led_at <= animacao_1;
                                        end if;

                                    when others => 
                                        estado_led_at <= animacao_1;
                                end case;
                            else
                                -- Counting finished (counter >= B): hold final value, zero flag if it is 0
                                resul <= balde_cont;
                                if balde_cont = "0000" then
                                    led_zero <= '1'; 
                                end if;
                            end if;

                        when "001" =>
                            -- Addition: 5-bit sum (bit 4 = carry). Note: vetor_ref is a signal, so the
                            -- flags/result below read its value from the previous clock cycle.
                            vetor_ref <= std_logic_vector(unsigned('0' & vetor_a) + unsigned('0' & vetor_b));
                            led_carry <= vetor_ref(4);
                            resul     <= vetor_ref(3 downto 0); 
                            
                            -- Overflow check: operands have the same sign bit and it differs from the result's
                            if (vetor_a(3) = vetor_b(3)) and (vetor_ref(4) /= vetor_a(3)) then
                                led_overflow <= '1';
                            end if;
                            
                            if vetor_ref(3 downto 0) = "0000" then
                                led_zero <= '1';
                            end if;

                            -- Negative flag = MSB of the 4-bit result
                            if vetor_ref(3) = '1' then
                                led_negative <= '1';
                            end if;

                        when "010" =>
                            -- Subtraction A - B, same flag logic as addition (bit 4 acts as borrow/carry)
                            vetor_ref <= std_logic_vector(unsigned('0' & vetor_a) - unsigned('0' & vetor_b));
                            led_carry <= vetor_ref(4);
                            resul     <= vetor_ref(3 downto 0); 
                            
                            if (vetor_a(3) = vetor_b(3)) and (vetor_ref(4) /= vetor_a(3)) then
                                led_overflow <= '1';
                            end if;
                            
                            if vetor_ref(3 downto 0) = "0000" then
                                led_zero <= '1';
                            end if;

                            if vetor_ref(3) = '1' then
                                led_negative <= '1';
                            end if;

                        when "011" =>
                            -- Minimum of A and B (signed comparison)
                            if signed(vetor_a) <= signed(vetor_b) then
                                vetor_ref <= '0' & vetor_a;
                            else
                                vetor_ref <= '0' & vetor_b;
                            end if;

                            if vetor_ref(3 downto 0) = "0000" then
                                led_zero <= '1';
                            end if;

                            if vetor_ref(3) = '1' then
                                led_negative <= '1';
                            end if;
                            resul <= vetor_ref(3 downto 0); 

                        when "100" =>
                            -- Maximum of A and B (signed comparison)
                            if signed(vetor_a) >= signed(vetor_b) then
                                vetor_ref <= '0' & vetor_a;
                            else
                                vetor_ref <= '0' & vetor_b;
                            end if;

                            if vetor_ref(3 downto 0) = "0000" then
                                led_zero <= '1';
                            end if;

                            if vetor_ref(3) = '1' then
                                led_negative <= '1';
                            end if;
                            resul <= vetor_ref(3 downto 0);

                        when "101" =>
                            -- Signed average: (A + B) / 2, computed in integer arithmetic and resized to 5 bits
                            vetor_ref <= std_logic_vector(to_signed(
                                (to_integer(signed(vetor_a)) + to_integer(signed(vetor_b))) / 2, 5));

                            if vetor_ref(3 downto 0) = "0000" then
                                led_zero <= '1';
                            end if;

                            if vetor_ref(3) = '1' then
                                led_negative <= '1';
                            end if;
                            resul <= vetor_ref(3 downto 0);

                        when "110" =>
                            -- Bitwise OR
                            vetor_ref <= ('0' & vetor_a) or ('0' & vetor_b);

                            if vetor_ref(3 downto 0) = "0000" then
                                led_zero <= '1';
                            end if;
                            resul <= vetor_ref(3 downto 0);
                        
                        when "111" =>
                            -- Bitwise AND
                            vetor_ref <= ('0' & vetor_a) and ('0' & vetor_b);
                            
                            if vetor_ref(3 downto 0) = "0000" then
                                led_zero <= '1';
                            end if;
                            resul <= vetor_ref(3 downto 0);

                        when others =>
                            resul <= (others => '0');
                    end case;

                    -- Pressing confirm again leaves execution and returns to operation selection
                    if confirm_pulso = '1' then
                        ref_cont     <= 0;
                        estado_atual <= espera_sel;
                    end if;

                when others =>
                    -- Safety fallback for undefined states
                    estado_atual <= espera_sel;
            end case;
        end if;
    end process;
end comportamento;