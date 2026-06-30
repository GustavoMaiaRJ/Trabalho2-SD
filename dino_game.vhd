-- PROJECT: GOOGLE DINOSAUR GAME (LCD + PS/2 KEYBOARD)

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Dino_Game is
    Port (
        CLK     : in  STD_LOGIC;                      -- 50 MHz Board Clock
        PS2_CLK : in  STD_LOGIC;                      -- Keyboard Clock
        PS2_DAT : in  STD_LOGIC;                      -- Keyboard Data
        LCD_RS  : out STD_LOGIC;                      -- LCD Register Select
        LCD_RW  : out STD_LOGIC;                      -- LCD Read/Write
        LCD_E   : out STD_LOGIC;                      -- LCD Enable
        LCD_DB  : out STD_LOGIC_VECTOR (7 downto 0);  -- LCD Data Bus
        LED     : out STD_LOGIC_VECTOR (7 downto 0)   -- Debug LEDs
    );
end Dino_Game;

architecture Behavioral of Dino_Game is

    -- PS/2 KEYBOARD SIGNALS
    signal ps2_filter    : std_logic_vector(7 downto 0) := (others => '1');
    signal ps2_clk_clean : std_logic := '1';
    signal ps2_clk_prev  : std_logic := '1';
    signal idle_count    : integer range 0 to 250000 := 0; -- 5ms Timeout
    
    signal ps2_fall      : std_logic;
    signal ps2_shift_reg : std_logic_vector(10 downto 0) := (others => '0');
    signal ps2_bit_count : integer range 0 to 11 := 0;
    signal ps2_done      : std_logic := '0';
    
    signal break_code    : std_logic := '0';
    signal jump_pulse    : std_logic := '0';

    -- GAME LOGIC SIGNALS
    type game_state_t is (ST_MENU, ST_PLAYING, ST_GAMEOVER);
    signal game_state    : game_state_t := ST_MENU;
    
    signal game_tick     : std_logic := '0';
    signal tick_counter  : integer range 0 to 7500000 := 0; -- 150ms at 50MHz
    
    signal jump_req      : std_logic := '0';
    signal dino_y        : integer range 0 to 1 := 1; -- 1=Ground, 0=Air
    signal jump_timer    : integer range 0 to 7 := 0;
    signal cactus_x      : integer range 0 to 15 := 15;
    signal collision     : std_logic := '0';

    -- LCD & SCREEN BUFFER SIGNALS
    type string_16 is array(0 to 15) of std_logic_vector(7 downto 0);
    type screen_buffer_t is array (0 to 31) of std_logic_vector(7 downto 0);
    signal screen : screen_buffer_t;

    -- Hardcoded ASCII Texts for Menus
    constant MENU_L1 : string_16 := (x"20", x"20", x"44", x"49", x"4E", x"4F", x"20", x"47", x"41", x"4D", x"45", x"20", x"20", x"20", x"20", x"20");
    constant MENU_L2 : string_16 := (x"20", x"50", x"52", x"45", x"53", x"53", x"20", x"53", x"50", x"41", x"43", x"45", x"20", x"20", x"20", x"20");
    constant OVER_L1 : string_16 := (x"20", x"20", x"20", x"47", x"41", x"4D", x"45", x"20", x"4F", x"56", x"45", x"52", x"20", x"20", x"20", x"20");

    signal lcd_init_wait : integer range 0 to 2500000 := 0; -- 50ms delay
    signal lcd_delay_cnt : integer range 0 to 100000 := 0;  -- 2ms delay
    signal lcd_ptr       : integer range 0 to 63 := 0;
    
    signal lcd_e_int     : std_logic := '0';
    signal lcd_rs_next   : std_logic := '0';
    signal lcd_data_next : std_logic_vector(7 downto 0) := x"00";

begin

    LCD_RW <= '0'; 

    -- PROCESS 1: PS/2 RECEIVER
    process(CLK)
    begin
        if rising_edge(CLK) then
            
            ps2_filter <= PS2_CLK & ps2_filter(7 downto 1);
            if ps2_filter = "11111111" then
                ps2_clk_clean <= '1';
            elsif ps2_filter = "00000000" then
                ps2_clk_clean <= '0';
            end if;

            ps2_clk_prev <= ps2_clk_clean;
            ps2_fall <= ps2_clk_prev and (not ps2_clk_clean);

            if ps2_clk_clean = '1' then
                if idle_count < 250000 then
                    idle_count <= idle_count + 1;
                else
                    ps2_bit_count <= 0;
                end if;
            else
                idle_count <= 0;
            end if;

            if ps2_fall = '1' then
                ps2_shift_reg <= PS2_DAT & ps2_shift_reg(10 downto 1);
                if ps2_bit_count = 10 then
                    ps2_bit_count <= 0;
                    ps2_done <= '1';
                else
                    ps2_bit_count <= ps2_bit_count + 1;
                    ps2_done <= '0';
                end if;
            else
                ps2_done <= '0';
            end if;

            jump_pulse <= '0';
            if ps2_done = '1' then
                if ps2_shift_reg(8 downto 1) = x"F0" then
                    break_code <= '1';
                else
                    if break_code = '0' and ps2_shift_reg(8 downto 1) = x"29" then
                        jump_pulse <= '1';
                    end if;
                    break_code <= '0';
                end if;
            end if;
            
        end if;
    end process;

    -- PROCESS 2: GAME ENGINE & PHYSICS
    collision <= '1' when (game_state = ST_PLAYING and cactus_x = 2 and dino_y = 1) else '0';
    
    process(CLK)
    begin
        if rising_edge(CLK) then
            
            if tick_counter = 7500000 then
                tick_counter <= 0;
                game_tick <= '1';
            else
                tick_counter <= tick_counter + 1;
                game_tick <= '0';
            end if;

            if jump_pulse = '1' then
                jump_req <= '1';
            end if;

            if jump_req = '1' and game_state = ST_PLAYING and dino_y = 1 then
                dino_y <= 0;
                jump_timer <= 4; 
                jump_req <= '0';
            end if;

            if game_tick = '1' then
                if collision = '1' then
                    game_state <= ST_GAMEOVER;
                else
                    case game_state is
                        
                        when ST_MENU =>
                            if jump_req = '1' then
                                game_state <= ST_PLAYING;
                                cactus_x <= 15;
                                dino_y <= 1;
                                jump_req <= '0';
                            end if;
                            
                        when ST_PLAYING =>
                            if cactus_x = 0 then
                                cactus_x <= 15;
                            else
                                cactus_x <= cactus_x - 1;
                            end if;

                            if dino_y = 0 then
                                if jump_timer = 0 then
                                    dino_y <= 1;
                                else
                                    jump_timer <= jump_timer - 1;
                                end if;
                            end if;

                        when ST_GAMEOVER =>
                            if jump_req = '1' then
                                game_state <= ST_MENU;
                                jump_req <= '0';
                            end if;
                            
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- PROCESS 3: SCREEN BUFFER RENDERER
    process(game_state, cactus_x, dino_y)
    begin
        if game_state = ST_MENU then
            for i in 0 to 15 loop
                screen(i)    <= MENU_L1(i);
                screen(i+16) <= MENU_L2(i);
            end loop;
        elsif game_state = ST_GAMEOVER then
            for i in 0 to 15 loop
                screen(i)    <= OVER_L1(i);
                screen(i+16) <= MENU_L2(i);
            end loop;
        else
            for i in 0 to 31 loop
                screen(i) <= x"20";
            end loop;
            
            if dino_y = 0 then
                screen(2) <= x"00";
            else
                screen(16 + 2) <= x"00";
            end if;
            
            screen(16 + cactus_x) <= x"01";
        end if;
    end process;

    -- PROCESS 4: LCD CONTROLLER & CGRAM LOADER
    process(lcd_ptr, screen)
    begin
        case lcd_ptr is
            when 0 => lcd_rs_next <= '0'; lcd_data_next <= x"38"; 
            when 1 => lcd_rs_next <= '0'; lcd_data_next <= x"0C"; 
            when 2 => lcd_rs_next <= '0'; lcd_data_next <= x"01"; 
            when 3 => lcd_rs_next <= '0'; lcd_data_next <= x"06"; 
            
            when 4 => lcd_rs_next <= '0'; lcd_data_next <= x"40"; 
            when 5 => lcd_rs_next <= '1'; lcd_data_next <= x"07"; 
            when 6 => lcd_rs_next <= '1'; lcd_data_next <= x"05"; 
            when 7 => lcd_rs_next <= '1'; lcd_data_next <= x"07"; 
            when 8 => lcd_rs_next <= '1'; lcd_data_next <= x"16"; 
            when 9 => lcd_rs_next <= '1'; lcd_data_next <= x"1F"; 
            when 10=> lcd_rs_next <= '1'; lcd_data_next <= x"0E"; 
            when 11=> lcd_rs_next <= '1'; lcd_data_next <= x"0A"; 
            when 12=> lcd_rs_next <= '1'; lcd_data_next <= x"0A"; 
            
            when 13=> lcd_rs_next <= '0'; lcd_data_next <= x"48"; 
            when 14=> lcd_rs_next <= '1'; lcd_data_next <= x"04"; 
            when 15=> lcd_rs_next <= '1'; lcd_data_next <= x"05"; 
            when 16=> lcd_rs_next <= '1'; lcd_data_next <= x"15"; 
            when 17=> lcd_rs_next <= '1'; lcd_data_next <= x"15"; 
            when 18=> lcd_rs_next <= '1'; lcd_data_next <= x"1F"; 
            when 19=> lcd_rs_next <= '1'; lcd_data_next <= x"04"; 
            when 20=> lcd_rs_next <= '1'; lcd_data_next <= x"04"; 
            when 21=> lcd_rs_next <= '1'; lcd_data_next <= x"04"; 

            when 22 => lcd_rs_next <= '0'; lcd_data_next <= x"80"; 
            when 23 to 38 => 
                lcd_rs_next <= '1';
                lcd_data_next <= screen(lcd_ptr - 23);
                
            when 39 => lcd_rs_next <= '0'; lcd_data_next <= x"C0";
            when 40 to 55 => 
                lcd_rs_next <= '1';
                lcd_data_next <= screen(lcd_ptr - 40 + 16);
                
            when others => lcd_rs_next <= '0'; lcd_data_next <= x"00";
        end case;
    end process;

    -- LCD Timing Control
    process(CLK)
    begin
        if rising_edge(CLK) then
            if lcd_init_wait < 2500000 then 
                lcd_init_wait <= lcd_init_wait + 1;
                lcd_e_int <= '0';
            else
                if lcd_delay_cnt < 100000 then 
                    lcd_delay_cnt <= lcd_delay_cnt + 1;
                else
                    lcd_delay_cnt <= 0;
                    if lcd_e_int = '0' then
                        lcd_e_int <= '1';
                    else
                        lcd_e_int <= '0';
                        if lcd_ptr = 55 then
                            lcd_ptr <= 22;
                        else
                            lcd_ptr <= lcd_ptr + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    LCD_RS <= lcd_rs_next;
    LCD_DB <= lcd_data_next;
    LCD_E  <= lcd_e_int;

    -- DEBUG LEDS
    LED(3 downto 0) <= std_logic_vector(to_unsigned(cactus_x, 4));
    LED(4) <= '1' when dino_y = 0 else '0';
    LED(5) <= jump_req;
    LED(7 downto 6) <= "00" when game_state = ST_MENU else
                       "01" when game_state = ST_PLAYING else "10";

end Behavioral;
