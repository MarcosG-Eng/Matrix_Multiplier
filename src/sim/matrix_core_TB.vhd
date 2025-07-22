library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

entity bram_dsp_mac_TB is
--  Port ( );
end bram_dsp_mac_TB;

architecture Behavioral of bram_dsp_mac_TB is

    component matrix_core is
    Generic (log2Acols : integer;
             log2Brows : integer;
             log2depth : integer;
             dataWidthAB : integer;
             dataWidthC : integer); --2*dataWidthAB + 2**log2depth - 1
    Port ( clock : in STD_LOGIC;

           --init signals
           load_in, validA_in, validB_in, validC_in : in STD_LOGIC;
           addrA_in : in STD_LOGIC_VECTOR(log2Acols+log2depth-1 downto 0);
           addrB_in : in STD_LOGIC_VECTOR(log2Brows+log2depth-1 downto 0);
           addrC_in : in STD_LOGIC_VECTOR(log2Acols+log2Brows-1 downto 0);
           a_in : in STD_LOGIC_VECTOR (dataWidthAB-1 downto 0);
           b_in : in STD_LOGIC_VECTOR (dataWidthAB-1 downto 0);
           c_in : in STD_LOGIC_VECTOR (dataWidthC-1 downto 0);

           --result signals
           cReady_out : out STD_LOGIC;
           readC_in : in STD_LOGIC;
           c_out : out STD_LOGIC_VECTOR (dataWidthC-1 downto 0));
    end component;
    
-- for first test case set:
--    constant log2Acols : integer := 2;
--    constant log2Brows : integer := 2;
--    constant log2depth : integer := 3;
--    constant dataWidthAB : integer := 8;
      --2*dataWidthAB + 2**log2depth - 1
--    constant dataWidthC : integer := 24;

-- for second test case set:
--    constant log2Acols : integer := 2;
--    constant log2Brows : integer := 2;
--    constant log2depth : integer := 4;
--    constant dataWidthAB : integer := 8;
      --2*dataWidthAB + 2**log2depth - 1
--    constant dataWidthC : integer := 24;

-- for third test case set:
    constant log2Acols : integer := 3;
    constant log2Brows : integer := 3;
    constant log2depth : integer := 4;
    constant dataWidthAB : integer := 8;
     --2*dataWidthAB + 2**log2depth - 1
    constant dataWidthC : integer := 24;
    
    signal clock :  STD_LOGIC;
    signal load_in, validA_in, validB_in, validC_in :  STD_LOGIC := '0';
    signal addrA_in :  STD_LOGIC_VECTOR(log2Acols+log2depth-1 downto 0);
    signal addrB_in :  STD_LOGIC_VECTOR(log2Brows+log2depth-1 downto 0);
    signal addrC_in :  STD_LOGIC_VECTOR(log2Acols+log2Brows-1 downto 0);
    signal a_in :  STD_LOGIC_VECTOR (dataWidthAB-1 downto 0);
    signal b_in :  STD_LOGIC_VECTOR (dataWidthAB-1 downto 0);
    signal c_in :  STD_LOGIC_VECTOR (dataWidthC-1 downto 0);
    signal cReady_out :  STD_LOGIC;
    signal readC_in :  STD_LOGIC := '0';
    signal c_out :  STD_LOGIC_VECTOR (dataWidthC-1 downto 0);
    
    signal reset :  STD_LOGIC;
    signal counter :  STD_LOGIC_VECTOR(log2Acols+log2depth downto 0);
    
    -- Signals for matrix readout
    type state_type is (LOADING, WAITING, READING, DONE);
    signal current_state : state_type := LOADING;
    signal read_counter : STD_LOGIC_VECTOR(log2Acols+log2Brows downto 0);
    signal matrix_complete : STD_LOGIC := '0';
    
    -- Array to store the result matrix for verification
    type result_matrix_type is array (0 to 2**(log2Acols+log2Brows)-1) of STD_LOGIC_VECTOR(dataWidthC-1 downto 0);
    signal result_matrix : result_matrix_type;

begin

    DUT_inst : matrix_core
    Generic map (log2Acols, log2Brows, log2depth, dataWidthAB, dataWidthC)
    Port map(clock, load_in, validA_in, validB_in, validC_in, addrA_in, addrB_in, addrC_in, a_in, b_in, c_in, cReady_out, readC_in, c_out);


    process begin
        clock <= '0';
        wait for 5 ns;
        clock <= '1';
        wait for 5 ns;
    end process;
    
    process begin
       reset <= '1';
       wait for 100 ns;
       reset <= '0';
       wait;
    end process;
    
    -- Combined process for loading and reading control
    process(clock) begin
        if rising_edge(clock) then
            if reset = '1' then
                counter <= (others => '0');
                load_in <= '0';
                validA_in <= '0';
                validB_in <= '0';
                validC_in <= '0';
                readC_in <= '0';
                current_state <= LOADING;
                read_counter <= (others => '0');
                matrix_complete <= '0';
            else
                case current_state is
                    when LOADING =>
                        -- Loading phase
                        if conv_integer(counter) < 2**(log2Acols+log2depth) then
                            validA_in <= '1';
                            validB_in <= '1';
                            validC_in <= '1';
                            load_in <= '1';
                            counter <= counter + '1';
                        else
                            validA_in <= '0';
                            validB_in <= '0';
                            validC_in <= '0';
                            load_in <= '0';
                            current_state <= WAITING;
                        end if;
                        
                        addrA_in <= counter(log2Acols+log2depth-1 downto 0);
                        addrB_in <= counter(log2Brows+log2depth-1 downto 0);
                        addrC_in <= counter(log2Acols+log2Brows-1 downto 0);
                        readC_in <= '0';
                        
                    when WAITING =>
                        -- Wait for cReady_out to indicate results are available
                        validA_in <= '0';
                        validB_in <= '0';
                        validC_in <= '0';
                        load_in <= '0';
                        readC_in <= '0';
                        
                        if cReady_out = '1' then
                            current_state <= READING;
                            read_counter <= (others => '0');
                        end if;
                        
                    when READING =>
                        -- Read all matrix elements
                        validA_in <= '0';
                        validB_in <= '0';
                        validC_in <= '0';
                        load_in <= '0';
                        readC_in <= '1';
                        
                        -- Set address BEFORE incrementing counter (for next cycle)
                        addrC_in <= read_counter(log2Acols+log2Brows-1 downto 0);
                        
                        if conv_integer(read_counter) < 2**(log2Acols+log2Brows) + 2 then
                            read_counter <= read_counter + '1';
                            
                            -- Store data only after 2 cycles of latency
                            if conv_integer(read_counter) >= 2 then
                                result_matrix(conv_integer(read_counter) - 2) <= c_out;
                            end if;
                        else
                            current_state <= DONE;
                            readC_in <= '0';
                            matrix_complete <= '1';
                        end if;
                        
                    when DONE =>
                        -- Matrix readout complete
                        validA_in <= '0';
                        validB_in <= '0';
                        validC_in <= '0';
                        load_in <= '0';
                        readC_in <= '0';
                        matrix_complete <= '1';
                end case;
                
-- uncomment for 1st test case
--                a_in <= ("00" & counter) + '1';
--                b_in <= x"40" - ("00" & counter);
--                c_in <= x"0000" & "00" & counter;

-- uncomment for 2nd test case
--                a_in <= ("0" & counter) + '1';
--                b_in <= x"40" - ("0" & counter);
--                c_in <= x"0000" & "0" & counter;
            
-- uncomment for 3rd test case           
                a_in <= counter + '1';
                b_in <= x"40" - counter;
                c_in <= x"0000" & counter;
            end if;
        end if;
    end process;
    
    -- Process to display the result matrix when complete
    process(matrix_complete)
        variable row, col : integer;
    begin
        if matrix_complete = '1' then
            report "Matrix multiplication result:";
            for i in 0 to 2**(log2Acols+log2Brows)-1 loop
                row := i / (2**log2Brows);
                col := i mod (2**log2Brows);
                if col = 0 then
                    report "Row " & integer'image(row) & ":";
                end if;
                report "  C[" & integer'image(row) & "][" & integer'image(col) & "] = " & 
                       integer'image(conv_integer(result_matrix(i)));
            end loop;
        end if;
    end process;
 
-- Expected matrices: C += A * B'

-- 1st  

-- 8311 10134 11957 13780
-- 5971  7282  8593  9904
-- 3631  4430  5229  6028
-- 1291  1578  1865  2152

-- 2nd

--  7392    5217    3042     867
-- 21860   15589    9318    3047
-- 36328   25961   15594    5227
-- 50796   36333   21870    7407

-- 3rd

--   7408     5233     3058      883    33268    31349    29174    26999
--- 21880    15609     9338     3067    92796    90877    84606    78335
--  36352    25985    15618     5251   152324   150405   140038   129671
--  50824    36361    21898     7435   211852   209933   195470   181007
--  65296    46737    28178     9619   271380   269461   250902   232343
--  79768    57113    34458    11803   330908   328989   306334   283679
--  94240    67489    40738    13987   390436   388517   361766   335015
-- 108712    77865    47018    16171   449964   448045   417198   386351

end Behavioral;
