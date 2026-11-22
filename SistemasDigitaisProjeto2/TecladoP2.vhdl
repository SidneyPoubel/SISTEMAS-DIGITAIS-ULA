----------------------------------------------------------------------------------
-- Project: PS/2 keyboard to LCD with Morse translation (maximum 5 characters)
-- Target board: Xilinx Spartan-3AN (50 MHz clock)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity teclado_morse_lcd is
    Port ( 
        clk         : in  STD_LOGIC;                    
        rst         : in  STD_LOGIC;                    
        ps2_clk     : in  STD_LOGIC;                    
        ps2_data    : in  STD_LOGIC;                    
        lcd_rs      : out STD_LOGIC;                    
        lcd_rw      : out STD_LOGIC;                    
        lcd_e       : out STD_LOGIC;                    
        lcd_data    : out STD_LOGIC_VECTOR (3 downto 0) -- 4-bit LCD interface (D7..D4)
    );
end teclado_morse_lcd;

architecture Behavioral of teclado_morse_lcd is

    -- PS/2 receiver signals
    signal ps2_clk_f      : std_logic_vector(1 downto 0) := "11"; -- 2-stage shift register for ps2_clk (synchronizer + edge detection)
    signal ps2_data_reg   : std_logic_vector(10 downto 0) := (others => '0'); -- Shift register for one PS/2 frame (start + 8 data + parity + stop)
    signal bit_count      : integer range 0 to 11 := 0;
    signal scan_code      : std_logic_vector(7 downto 0) := (others => '0');
    signal scan_ready     : std_logic := '0'; -- One-clock pulse when a new scan code is available

    -- Text buffers (limit: 5 ASCII characters)
    type char_array is array (0 to 4) of std_logic_vector(7 downto 0);
    signal buffer_ascii   : char_array := (others => x"20");
    signal char_count     : integer range 0 to 5 := 0;

    -- Morse buffer (up to 16 positions, one ASCII symbol per position)
    type morse_array is array (0 to 15) of std_logic_vector(7 downto 0);
    signal buffer_morse   : morse_array := (others => x"20");
    
    -- Number of Morse positions used by each typed character (needed for backspace)
    type len_array is array (0 to 4) of integer range 0 to 5;
    signal morse_lens     : len_array := (others => 0);
    signal morse_count    : integer range 0 to 16 := 0; -- Total Morse positions currently used

    -- LCD time base generator
    signal clk_cnt        : integer := 0;
    signal lcd_tick       : std_logic := '0';

    -- LCD state machine
    type state_type is (
        ST_RESET, 
        INIT_1, INIT_2, INIT_3, INIT_4, INIT_5, INIT_6, INIT_7,
        SET_LINE1, WRITE_LINE1, 
        SET_LINE2, WRITE_LINE2,
        DELAY_HOLD
    );
    signal state      : state_type := ST_RESET;
    signal sub_step   : integer range 0 to 4 := 0; -- Phase inside a byte transfer (see send_byte)
    signal write_idx  : integer range 0 to 16 := 0; -- Index of the character being written to the LCD

begin

    lcd_rw <= '0'; -- Write-only: the LCD is never read

    ------------------------------------------------------------------------------
    -- BLOCK 1: PS/2 DATA RECEIVER
    ------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                ps2_clk_f    <= "11";
                bit_count    <= 0;
                scan_ready   <= '0';
            else
                ps2_clk_f(0) <= ps2_clk;
                ps2_clk_f(1) <= ps2_clk_f(0);
                
                scan_ready <= '0';
                
                -- Falling edge of ps2_clk detected: PS/2 data is valid on this edge
                if ps2_clk_f = "10" then
                    -- Bits arrive LSB first, so each new bit enters at the MSB and the register shifts right
                    ps2_data_reg <= ps2_data & ps2_data_reg(10 downto 1);
                    if bit_count = 10 then
                        -- The register still holds the previous 10 bits (start..parity):
                        -- bits 9 downto 2 are the data byte D7..D0
                        scan_code  <= ps2_data_reg(9 downto 2);
                        scan_ready <= '1';
                        bit_count  <= 0;
                    else
                        bit_count  <= bit_count + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------
    -- BLOCK 2: SCAN CODE -> ASCII & MORSE TRANSLATOR
    ------------------------------------------------------------------------------
    process(clk)
        variable is_break_code : boolean := false; -- True after F0 (key release); the next scan code must be ignored
        variable sym           : std_logic_vector(39 downto 0); 
        variable sym_len       : integer range 0 to 5 := 0;
        variable ascii_val     : std_logic_vector(7 downto 0);
        variable valid_key     : boolean := false;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                char_count   <= 0;
                morse_count  <= 0;
                buffer_ascii <= (others => x"20");
                buffer_morse <= (others => x"20");
                morse_lens   <= (others => 0);
                is_break_code := false;
            elsif scan_ready = '1' then
                
                if scan_code = x"F0" then
                    is_break_code := true;
                elsif is_break_code then
                    is_break_code := false; -- Discard the scan code of the released key
                else
                    valid_key := false;
                    sym_len   := 0;
                    -- Fill all 5 bytes with space (0x20)
                    sym       := x"2020202020";

                    -- sym is 40 bits wide (5 bytes) and every assignment below drives exactly 40 bits.
                    -- Byte 1 (39 downto 32) is the first Morse symbol ('.' = 0x2E, '-' = 0x2D).
                    -- sym_len is the number of Morse symbols plus one trailing separator position.
                    case scan_code is
                        when x"1C" => ascii_val := x"41"; sym := x"2E2D202020"; sym_len := 3; valid_key := true; -- A  .-
                        when x"32" => ascii_val := x"42"; sym := x"2D2E2E2E20"; sym_len := 5; valid_key := true; -- B  -...
                        when x"21" => ascii_val := x"43"; sym := x"2D2E2D2E20"; sym_len := 5; valid_key := true; -- C  -.-.
                        when x"23" => ascii_val := x"44"; sym := x"2D2E2E2020"; sym_len := 4; valid_key := true; -- D  -..
                        when x"24" => ascii_val := x"45"; sym := x"2E20202020"; sym_len := 2; valid_key := true; -- E  .
                        when x"2B" => ascii_val := x"46"; sym := x"2E2E2D2E20"; sym_len := 5; valid_key := true; -- F  ..-.
                        when x"34" => ascii_val := x"47"; sym := x"2D2D2E2020"; sym_len := 4; valid_key := true; -- G  --.
                        when x"33" => ascii_val := x"48"; sym := x"2E2E2E2E20"; sym_len := 5; valid_key := true; -- H  ....
                        when x"43" => ascii_val := x"49"; sym := x"2E2E202020"; sym_len := 3; valid_key := true; -- I  ..
                        when x"3B" => ascii_val := x"4A"; sym := x"2E2D2D2D20"; sym_len := 5; valid_key := true; -- J  .---
                        when x"42" => ascii_val := x"4B"; sym := x"2D2E2D2020"; sym_len := 4; valid_key := true; -- K  -.-
                        when x"4B" => ascii_val := x"4C"; sym := x"2E2D2E2E20"; sym_len := 5; valid_key := true; -- L  .-..
                        when x"3A" => ascii_val := x"4D"; sym := x"2D2D202020"; sym_len := 3; valid_key := true; -- M  --
                        when x"31" => ascii_val := x"4E"; sym := x"2D2E202020"; sym_len := 3; valid_key := true; -- N  -.
                        when x"44" => ascii_val := x"4F"; sym := x"2D2D2D2020"; sym_len := 4; valid_key := true; -- O  ---
                        when x"4D" => ascii_val := x"50"; sym := x"2E2D2D2E20"; sym_len := 5; valid_key := true; -- P  .--.
                        when x"15" => ascii_val := x"51"; sym := x"2D2D2E2D20"; sym_len := 5; valid_key := true; -- Q  --.-
                        when x"2D" => ascii_val := x"52"; sym := x"2E2D2E2020"; sym_len := 4; valid_key := true; -- R  .-.
                        when x"1B" => ascii_val := x"53"; sym := x"2E2E2E2020"; sym_len := 4; valid_key := true; -- S  ...
                        when x"2C" => ascii_val := x"54"; sym := x"2D20202020"; sym_len := 2; valid_key := true; -- T  -
                        when x"3C" => ascii_val := x"55"; sym := x"2E2E2D2020"; sym_len := 4; valid_key := true; -- U  ..-
                        when x"2A" => ascii_val := x"56"; sym := x"2E2E2E2D20"; sym_len := 5; valid_key := true; -- V  ...-
                        when x"1D" => ascii_val := x"57"; sym := x"2E2D2D2020"; sym_len := 4; valid_key := true; -- W  .--
                        when x"22" => ascii_val := x"58"; sym := x"2D2E2E2D20"; sym_len := 5; valid_key := true; -- X  -..-
                        when x"35" => ascii_val := x"59"; sym := x"2D2E2D2D20"; sym_len := 5; valid_key := true; -- Y  -.--
                        when x"1A" => ascii_val := x"5A"; sym := x"2D2D2E2E20"; sym_len := 5; valid_key := true; -- Z  --..
                        when x"29" => ascii_val := x"20"; sym := x"2020202020"; sym_len := 3; valid_key := true; -- SPACE

                        -- Backspace: erase the last character and its Morse symbols
                        when x"66" =>
                            if char_count > 0 then
                                buffer_ascii(char_count - 1) <= x"20";
                                for i in 0 to 4 loop
                                    if i < morse_lens(char_count - 1) then
                                        buffer_morse(morse_count - 1 - i) <= x"20";
                                    end if;
                                end loop;
                                morse_count <= morse_count - morse_lens(char_count - 1);
                                char_count  <= char_count - 1;
                            end if;

                        when others => null;
                    end case;

                    -- Append the new character and its Morse symbols after the existing ones
                    if valid_key and char_count < 5 then
                        buffer_ascii(char_count) <= ascii_val;
                        morse_lens(char_count)   <= sym_len;
                        
                        -- sym is always 40 bits, so every slice below is within bounds.
                        -- Only the first sym_len bytes are written to the Morse buffer.
                        if sym_len >= 1 then buffer_morse(morse_count)     <= sym(39 downto 32); end if;
                        if sym_len >= 2 then buffer_morse(morse_count + 1) <= sym(31 downto 24); end if;
                        if sym_len >= 3 then buffer_morse(morse_count + 2) <= sym(23 downto 16); end if;
                        if sym_len >= 4 then buffer_morse(morse_count + 3) <= sym(15 downto 8);  end if;
                        if sym_len >= 5 then buffer_morse(morse_count + 4) <= sym(7 downto 0);   end if;

                        morse_count <= morse_count + sym_len;
                        char_count  <= char_count + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------
    -- BLOCK 3: LCD TIME BASE (Reminder: reduce the count for simulation)
    ------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            -- Change to 'clk_cnt = 5' if simulating in ModelSim!
            -- (note: the value currently in the code is already 5)
            -- lcd_tick pulses once every (limit + 1) clock cycles and paces the LCD state machine
            if clk_cnt = 5 then 
                lcd_tick <= '1';
                clk_cnt <= 0;
            else
                lcd_tick <= '0';
                clk_cnt <= clk_cnt + 1;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------
    -- BLOCK 4: LCD FSM CONTROLLER
    ------------------------------------------------------------------------------
    process(clk)
        -- Sends one byte to the LCD in 4-bit mode, one step per call:
        --   step 0: high nibble on the bus, E high
        --   step 1: E low (high nibble latched on the falling edge)
        --   step 2: low nibble on the bus, E high
        --   step 3: E low (low nibble latched)
        -- is_data selects RS: '0' = command, '1' = character data
        procedure send_byte(
            val       : in std_logic_vector(7 downto 0);
            is_data   : in std_logic;
            step      : in integer;
            signal e  : out std_logic;
            signal rs : out std_logic;
            signal d  : out std_logic_vector(3 downto 0)
        ) is
        begin
            rs <= is_data;
            case step is
                when 0 => 
                    d <= val(7 downto 4);
                    e <= '1';
                when 1 => 
                    e <= '0';
                when 2 => 
                    d <= val(3 downto 0);
                    e <= '1';
                when 3 => 
                    e <= '0';
                when others => null;
            end case;
        end procedure;

    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= ST_RESET;
                sub_step  <= 0;
                write_idx <= 0;
                lcd_e     <= '0';
                lcd_rs    <= '0';
                lcd_data  <= "0000";
            elsif lcd_tick = '1' then

                case state is

                    when ST_RESET =>
                        sub_step <= 0;
                        state    <= INIT_1;

                    -- Initialization sequence: switch the LCD to 4-bit mode and configure it
                    when INIT_1 => 
                        send_byte(x"33", '0', sub_step, lcd_e, lcd_rs, lcd_data);
                        if sub_step = 3 then sub_step <= 0; state <= INIT_2; else sub_step <= sub_step + 1; end if;

                    when INIT_2 => 
                        send_byte(x"32", '0', sub_step, lcd_e, lcd_rs, lcd_data);
                        if sub_step = 3 then sub_step <= 0; state <= INIT_3; else sub_step <= sub_step + 1; end if;

                    -- Function set: 4-bit interface, 2 lines, 5x8 font
                    when INIT_3 => 
                        send_byte(x"28", '0', sub_step, lcd_e, lcd_rs, lcd_data);
                        if sub_step = 3 then sub_step <= 0; state <= INIT_4; else sub_step <= sub_step + 1; end if;

                    -- Display on, cursor off, blink off
                    when INIT_4 => 
                        send_byte(x"0C", '0', sub_step, lcd_e, lcd_rs, lcd_data);
                        if sub_step = 3 then sub_step <= 0; state <= INIT_5; else sub_step <= sub_step + 1; end if;

                    -- Clear display
                    when INIT_5 => 
                        send_byte(x"01", '0', sub_step, lcd_e, lcd_rs, lcd_data);
                        if sub_step = 3 then sub_step <= 0; state <= INIT_6; else sub_step <= sub_step + 1; end if;

                    -- Entry mode: cursor moves right, no display shift
                    when INIT_6 => 
                        send_byte(x"06", '0', sub_step, lcd_e, lcd_rs, lcd_data);
                        if sub_step = 3 then sub_step <= 0; state <= INIT_7; else sub_step <= sub_step + 1; end if;

                    when INIT_7 =>
                        state <= SET_LINE1;

                    -- Main loop: continuously refresh both LCD lines from the buffers
                    -- Set DDRAM address to the start of line 1
                    when SET_LINE1 => 
                        send_byte(x"80", '0', sub_step, lcd_e, lcd_rs, lcd_data);
                        if sub_step = 3 then 
                            sub_step  <= 0; 
                            write_idx <= 0; 
                            state     <= WRITE_LINE1; 
                        else 
                            sub_step <= sub_step + 1; 
                        end if;

                    -- Line 1: typed ASCII characters
                    when WRITE_LINE1 => 
                        if write_idx < 5 then
                            send_byte(buffer_ascii(write_idx), '1', sub_step, lcd_e, lcd_rs, lcd_data);
                            if sub_step = 3 then 
                                sub_step  <= 0; 
                                write_idx <= write_idx + 1; 
                            else 
                                sub_step  <= sub_step + 1; 
                            end if;
                        else
                            state <= SET_LINE2;
                        end if;

                    -- Set DDRAM address to the start of line 2
                    when SET_LINE2 => 
                        send_byte(x"C0", '0', sub_step, lcd_e, lcd_rs, lcd_data);
                        if sub_step = 3 then 
                            sub_step  <= 0; 
                            write_idx <= 0; 
                            state     <= WRITE_LINE2; 
                        else 
                            sub_step <= sub_step + 1; 
                        end if;

                    -- Line 2: Morse translation (all 16 positions)
                    when WRITE_LINE2 => 
                        if write_idx < 16 then
                            send_byte(buffer_morse(write_idx), '1', sub_step, lcd_e, lcd_rs, lcd_data);
                            if sub_step = 3 then 
                                sub_step  <= 0; 
                                write_idx <= write_idx + 1; 
                            else 
                                sub_step  <= sub_step + 1; 
                            end if;
                        else
                            state <= DELAY_HOLD;
                        end if;

                    when DELAY_HOLD => 
                        state <= SET_LINE1;

                    when others =>
                        state <= ST_RESET;

                end case;
            end if;
        end if;
    end process;

end Behavioral;