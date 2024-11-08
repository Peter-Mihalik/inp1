
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
    signal pc: std_logic_vector(12 downto 0) := (others => '0');
    signal pc_inc: std_logic;
    signal pc_dec: std_logic;
    -- PTR Signals
    signal ptr: std_logic_vector(12 downto 0) := (others => '0');
    signal ptr_inc: std_logic;
    signal ptr_dec: std_logic;
    -- TMP
    signal tmp: std_logic_vector(7 downto 0);
    signal tmp_ld: std_logic;
    -- MUX1
    signal mux1_sel: std_logic;
    signal mux2_sel: std_logic_vector(1 downto 0);
    -- FSM
    type state_type is (s_idle, s_load, s_read_sep, s_fetch, s_decode, s_ptr_inc, s_ptr_dec, s_mem_inc, s_mem_dec,
    s_read_mem, s_tmp_load, s_tmp_store, s_out_busy, s_print, s_in_req, s_in_store, s_jmp_f, s_jmp_b, s_left_bracket, 
    s_right_bracket, s_wait_left_bracket, s_wait_right_bracket, s_halt);
    signal pstate: state_type := s_idle;
    signal nstate: state_type;
    signal found_sep: std_logic;

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
    tmp_proc: process (CLK, RESET)
    begin
        if CLK'event and CLK='1' then
            if tmp_ld='1' then
                tmp <= DATA_RDATA; 
            end if;
        elsif RESET = '1' then
          tmp <= (others => '0');
        end if;
    end process;

    -- CNT
    cnt_reg_proc: process (CLK, RESET)
    begin
      
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

    -- FSM
    -- State Register
    state_reg_proc: process (CLK, RESET)
    begin
      if RESET='1' then
        pstate <= s_idle;
      elsif CLK'event and CLK='1' then
        if EN='1' then
          pstate <= nstate;
        end if;
      end if;
    end process;

    -- Next State Logic
    nstate_log_proc: process (pstate, EN, DATA_RDATA, OUT_BUSY, IN_DATA)
    begin
      -- INIT
      pc_inc <= '0';
      pc_dec <= '0';
      ptr_inc <= '0';
      ptr_dec <= '0';
      DATA_EN <= '0';
      DATA_RDWR <= '0';
      mux1_sel <= '0';
      mux2_sel <= "00";
      tmp_ld <= '0';
      OUT_WE <= '0';
      OUT_DATA <= X"00";
      OUT_INV <= '1';
      IN_REQ <= '0';

      case pstate is
        -- IDLE
        when s_idle =>
          READY <= '0';
          DONE <= '0';
          
          if EN='1' then
            nstate <= s_load;
          else
            nstate <= s_idle;
          end if;
          
        -- Load program - find separator and set PTR
        when s_load =>
          DATA_RDWR <= '1';
          DATA_EN <= '1';
          mux1_sel <= '0';
          nstate <= s_read_sep;

        -- READ SEPARATOR
        when s_read_sep =>
            ptr_inc <= '1';
          if DATA_RDATA=X"40" then
            READY <= '1';
            nstate <= s_fetch;
          else
            nstate <= s_load;
          end if;

        -- FETCH
        when s_fetch =>
          DATA_RDWR <= '1';
          DATA_EN <= '1';
          mux1_sel <= '1';
          nstate <= s_decode;


        -- DECODE
        when s_decode =>
          case DATA_RDATA is
           when X"3E" => nstate <= s_ptr_inc;
           when X"3C" => nstate <= s_ptr_dec;
           when X"2B" => nstate <= s_read_mem;
           when X"2D" => nstate <= s_read_mem;
           when X"5B" => nstate <= s_read_mem;
           when X"5D" => nstate <= s_read_mem;
           when X"24" => nstate <= s_read_mem;
           when X"21" => nstate <= s_tmp_store;
           when X"2E" => nstate <= s_out_busy;
           when X"2C" => nstate <= s_in_req;
            when X"40" => 
              nstate <= s_halt;
            when others => 
              pc_inc <= '1';
              nstate <= s_fetch;
          end case;  

        -- HALT
        when s_halt =>
          DONE <= '1';
          if RESET='1' then
            nstate <= s_idle;
          else
            nstate <= s_halt;
          end if;

        -- PTR Increment
        when s_ptr_inc =>
          ptr_inc <= '1';
          pc_inc <= '1';
          nstate <= s_fetch;

        -- PTR Decrement
        when s_ptr_dec =>
          ptr_dec <= '1';
          pc_inc <= '1';
          nstate <= s_fetch;

        -- Read From memory
        when s_read_mem =>
          DATA_RDWR <= '1';
          DATA_EN <= '1';
          mux1_sel <= '0'; -- read from ptr
          if DATA_RDATA = X"2B" then
            nstate <= s_mem_inc;
          elsif DATA_RDATA = X"2D" then
            nstate <= s_mem_dec;
          elsif DATA_RDATA = X"24" then
            nstate <= s_tmp_load;
          elsif DATA_RDATA = X"2E" then
            nstate <= s_print;
          elsif DATA_RDATA = X"5B" then
            nstate <= s_left_bracket;
          elsif DATA_RDATA = X"5D" then
            nstate <= s_right_bracket;
          end if;

        -- LOOPS
        -- [
        when s_left_bracket =>
            pc_inc <= '1';
          if DATA_RDATA = X"00" then
            nstate <= s_jmp_f;
          else 
            nstate <= s_fetch;
          end if;
        when s_jmp_f =>
          -- fetch and dont execute
          DATA_EN <= '1';
          DATA_RDWR <= '1';
          mux1_sel <= '1'; -- pc (instruction is read)
          nstate <= s_wait_right_bracket;
        when s_wait_right_bracket =>
          pc_inc <= '1';
          if DATA_RDATA = X"5D" then
            nstate <= s_fetch;
          else
            nstate <= s_jmp_f;
          end if;

        -- ]
        when s_right_bracket =>
          if DATA_RDATA = X"00" then
            pc_inc <= '1';
            nstate <= s_fetch;
          else
            pc_dec <= '1';
            nstate <= s_jmp_b;
          end if;
        when s_jmp_b =>
          DATA_EN <= '1';
          DATA_RDWR <= '1';
          mux1_sel <= '1';
          nstate <= s_wait_left_bracket;
        when s_wait_left_bracket =>
          if DATA_RDATA = X"5B" then
            pc_inc <= '1';
            nstate <= s_fetch;
          else 
            pc_dec <= '1';
            nstate <= s_jmp_b;
          end if;

        -- MEM Increment
        when s_mem_inc =>
          mux1_sel <= '0';
          mux2_sel <= "11";
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          pc_inc <= '1';
          nstate <= s_fetch;

        -- MEM Decrement
        when s_mem_dec =>
          mux1_sel <= '0';
          mux2_sel <= "10";
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          pc_inc <= '1';
          nstate <= s_fetch;

        -- Load into TMP
        when s_tmp_load =>
          tmp_ld <= '1';
          pc_inc <= '1';
          nstate <= s_fetch;

        -- Store TMP in memory
        when s_tmp_store =>
          mux1_sel <= '0';
          mux2_sel <= "01";
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          pc_inc <= '1';
          nstate <= s_fetch;
        
        -- Print memory
        when s_out_busy =>
          if OUT_BUSY = '1' then
            nstate <= s_out_busy;
          elsif OUT_BUSY = '0' then
            nstate <= s_read_mem;
          end if;
        when s_print =>
          OUT_WE <= '1';
          OUT_INV <= '0';
          OUT_DATA <= DATA_RDATA;
          pc_inc <= '1';
          nstate <= s_fetch;

        -- Store Input
        when s_in_req =>
          IN_REQ <= '1';
          if IN_VLD = '0' then
            nstate <= s_in_req;
          elsif IN_VLD = '1' then
            nstate <= s_in_store;
          end if;
        when s_in_store =>
          mux1_sel <= '0';
          mux2_sel <= "00";
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          pc_inc <= '1';
          nstate <= s_fetch;


          
              
        end case;
      

    end process;


    

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 

end behavioral;

