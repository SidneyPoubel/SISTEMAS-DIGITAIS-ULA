library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_teclado is
end tb_teclado;

architecture behavior of tb_teclado is

    -- Component declaration for the design under test
    component teclado_morse_lcd
    Port (
        clk         : in  STD_LOGIC;
        rst         : in  STD_LOGIC;
        ps2_clk     : in  STD_LOGIC;
        ps2_data    : in  STD_LOGIC;
        lcd_rs      : out STD_LOGIC;
        lcd_rw      : out STD_LOGIC;
        lcd_e       : out STD_LOGIC;
        lcd_data    : out STD_LOGIC_VECTOR (3 downto 0)
    );
    end component;

    -- Test inputs (PS/2 lines idle high)
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '0';
    signal ps2_clk  : std_logic := '1';
    signal ps2_data : std_logic := '1';

    -- Test outputs
    signal lcd_rs   : std_logic;
    signal lcd_rw   : std_logic;
    signal lcd_e    : std_logic;
    signal lcd_data : std_logic_vector(3 downto 0);

    -- System clock period (50 MHz)
    constant clk_period : time := 20 ns;

begin

    -- Unit Under Test
    uut: teclado_morse_lcd PORT MAP (
        clk => clk,
        rst => rst,
        ps2_clk => ps2_clk,
        ps2_data => ps2_data,
        lcd_rs => lcd_rs,
        lcd_rw => lcd_rw,
        lcd_e => lcd_e,
        lcd_data => lcd_data
    );

    -- Free-running system clock
    clk_process :process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;

    -- Stimulus process (injects key presses)
    stim_proc: process
        
        -- Emulates a keyboard sending one PS/2 frame:
        -- start bit, 8 data bits (LSB first), odd parity bit, stop bit.
        -- Data is placed 20 us before ps2_clk falls, so it is stable at the falling edge
        -- (the point where the DUT samples it). ps2_clk period is 80 us.
        procedure send_ps2_code (
            constant code : in std_logic_vector(7 downto 0);
            signal clk_out : out std_logic;
            signal dat_out : out std_logic
        ) is
            variable parity : std_logic;
        begin
            -- Odd parity: the parity bit makes the total number of '1' bits (data + parity) odd
            parity := not (code(0) xor code(1) xor code(2) xor code(3) xor code(4) xor code(5) xor code(6) xor code(7));

            -- 1. Start bit
            dat_out <= '0'; wait for 20 us;
            clk_out <= '0'; wait for 40 us; clk_out <= '1'; wait for 20 us;

            -- 2. Data bits
            for i in 0 to 7 loop
                dat_out <= code(i); wait for 20 us;
                clk_out <= '0'; wait for 40 us; clk_out <= '1'; wait for 20 us;
            end loop;

            -- 3. Parity bit
            dat_out <= parity; wait for 20 us;
            clk_out <= '0'; wait for 40 us; clk_out <= '1'; wait for 20 us;

            -- 4. Stop bit
            dat_out <= '1'; wait for 20 us;
            clk_out <= '0'; wait for 40 us; clk_out <= '1'; wait for 20 us;

            -- Idle gap before the next scan code
            wait for 1 ms;
        end procedure;

    begin
        -- Initial state and reset
        ps2_clk  <= '1';
        ps2_data <= '1';
        rst <= '1';
        wait for 100 ns;
        rst <= '0';

        -- Wait for the LCD to complete its initialization routine (~15 ms)
        wait for 16 ms;

        -- Send key "A" (scan code 0x1C)
        send_ps2_code(x"1C", ps2_clk, ps2_data);
        wait for 2 ms;
        
        -- Send key "B" (scan code 0x32)
        send_ps2_code(x"32", ps2_clk, ps2_data);
        wait for 2 ms;
        
        -- Simulate the release of key "B" (break code 0xF0 followed by its scan code)
        send_ps2_code(x"F0", ps2_clk, ps2_data);
        send_ps2_code(x"32", ps2_clk, ps2_data);

        wait; -- End of stimulus
    end process;

end behavior;