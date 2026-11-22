library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Button debouncer: the input must stay stable for 25M clock cycles
-- (~0.5 s at 50 MHz, assuming that clock) before the output changes.
-- Also generates a single-cycle pulse on each rising edge of the debounced signal.
entity debounce_ula is
    port(
        clk        : in  std_logic;
        confirm    : in  std_logic;  -- raw (noisy) button input
        confirm_db : out std_logic;  -- debounced level
        pulso      : out std_logic   -- one-clock-cycle pulse when the debounced signal goes 0 -> 1
    );
end debounce_ula;

architecture comportamento of debounce_ula is
    signal confirm_ant      : std_logic := '0';  -- previous sampled value of the raw input
    signal contagem         : integer range 0 to 25000000 := 0;  -- counts consecutive cycles with a stable input
    signal confirm_db_ant   : std_logic := '0';  -- previous debounced value (used for edge detection)
    signal confirm_db_sinal : std_logic := '0';  -- internal debounced signal
begin
    process (clk)
    begin
        if rising_edge(clk) then
            -- Both branches ('0' and '1') work the same way:
            -- if the input equals the previous sample, keep counting; once the count
            -- reaches the limit, the debounced signal takes the input's value.
            -- If the input changed, restart the count from 1.
            case confirm is
                when '0' =>
                    if confirm_ant = confirm then
                        if contagem < 25000000 then
                            confirm_ant <= confirm;
                            contagem    <= contagem + 1;
                        else
                            confirm_db_sinal <= '0';
                        end if;
                    else
                        contagem    <= 1;
                        confirm_ant <= confirm;
                    end if;

                when '1' =>
                    if confirm_ant = confirm then
                        if contagem < 25000000 then
                            confirm_ant <= confirm;
                            contagem    <= contagem + 1;
                        else
                            confirm_db_sinal <= '1';
                        end if;
                    else
                        contagem    <= 1;
                        confirm_ant <= confirm;
                    end if;
                
                when others =>
                    null;
            end case;
            -- Register the debounced value for the edge detector below
            confirm_db_ant <= confirm_db_sinal;
        end if;
    end process;

    confirm_db <= confirm_db_sinal;
    -- Rising-edge detector: high only when the current value is 1 and the previous was 0
    pulso      <= confirm_db_sinal and (not confirm_db_ant);
end comportamento;