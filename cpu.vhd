-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2024 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Peter Mihalik <xmihalp00>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (1) / zapis (0)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_INV  : out std_logic;                      -- pozadavek na aktivaci inverzniho zobrazeni (1)
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
    -- PC Signals
    signal pc: std_logic_vector(12 downto 0);
    signal pc_inc: std_logic;
    signal pc_dec: std_logic;
    -- PTR Signals
    signal ptr: std_logic_vector(12 downto 0);
    signal ptr_inc: std_logic;
    signal ptr_dec: std_logic;
    -- TMP
    signal tmp: std_logic_vector(7 downto 0);
    signal tmp_ld: std_logic;
    -- MUX1
    signal mux1_sel: std_logic;
    signal mux2_sel: std_logic_vector(1 downto 0);
    -- DEC
    type inst_type is (i_ptr_inc, i_ptr_dec, i_mem_inc, i_mem_dec, i_right_brac, 
        i_left_brac, i_tmp_load, i_tmp_store, i_mem_print, i_mem_scan, i_separ_term, i_nop);
    signal inst: inst_type;
    -- FSM

begin
    -- PC
    pc_proc: process (CLK, RESET)
    begin
        -- Increment or decrement counter
        if CLK'event and CLK='1' then
            if pc_inc='1' then
                if pc=8191 then -- Memory loop
                    pc <= (others => '0');
                else
                    pc <= pc + 1;
                end if;
            elsif pc_dec='1' then
                if pc=0 then -- Memory loop
                    pc <= (others => '1');
                else
                    pc <= pc - 1;
                end if;
            end if;
        elsif RESET='1' then
            pc <= (others => '0');
        end if;

    end process;

    -- PTR
    ptr_proc: process (CLK, RESET)
    begin
        if CLK'event and CLK='1' then
            if ptr_inc='1' then
                ptr <= ptr + 1;
            elsif ptr_dec='1' then
                ptr <= ptr - 1;
            end if;
        elsif RESET='1' then
            ptr <= (others => '0');
        end if;
    end process;
    

    -- TMP
    tmp_proc: process (CLK)
    begin
        if CLK'event and CLK='1' then
            if tmp_ld='1' then
                tmp <= DATA_RDATA; 
            end if;
        end if;
    end process;
    
    -- MUX1
    mux1_proc: process (pc, ptr, mux1_sel)
    begin
        case mux1_sel is
            when '0' => DATA_ADDR <= ptr;
            when '1' => DATA_ADDR <= pc;
            when others => null;
        end case;
    end process;

    -- MUX2
    mux2_proc: process (IN_DATA, tmp, DATA_RDATA, mux2_sel)
    begin
        case mux2_sel is
            when "00" => DATA_WDATA <= IN_DATA;
            when "01" => DATA_WDATA <= tmp;
            when "10" => DATA_WDATA <= DATA_RDATA - 1;
            when "11" => DATA_WDATA <= DATA_RDATA + 1;
            when others => null;
        end case;
    end process;

    -- Decoder
    decode: process (DATA_RDATA)
    begin
        case DATA_RDATA is
            when X"3E" => inst <= i_ptr_inc;
            when X"3C" => inst <= i_ptr_dec;
            when X"2B" => inst <= i_mem_inc;
            when X"2D" => inst <= i_mem_dec;
            when X"5B" => inst <= i_right_brac;
            when X"5D" => inst <= i_left_brac;
            when X"24" => inst <= i_tmp_load;
            when X"21" => inst <= i_tmp_store;
            when X"2E" => inst <= i_mem_print;
            when X"2C" => inst <= i_mem_scan;
            when X"40" => inst <= i_separ_term;
            when others => inst <= i_nop;
        end case;
    end process;


    

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 

end behavioral;

