library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

entity matrix_core_axi_wrapper_TB is
--  Port ( );
end matrix_core_axi_wrapper_TB;

architecture Behavioral of matrix_core_axi_wrapper_TB is

    component matrix_core_axi_wrapper is
    Generic (
        log2Acols : integer := 3;
        log2Brows : integer := 3;
        log2depth : integer := 4;
        dataWidthAB : integer := 8;
        dataWidthC : integer := 24
    );
    Port (
        -- Clock and Reset
        aclk : in STD_LOGIC;
        aresetn : in STD_LOGIC;
        
        -- AXI4-Stream Slave Interface (64-bit: Matrix A[63:32] + Matrix B[31:0])
        s_axis_tdata : in STD_LOGIC_VECTOR(63 downto 0);
        s_axis_tvalid : in STD_LOGIC;
        s_axis_tready : out STD_LOGIC;
        s_axis_tlast : in STD_LOGIC;
        
        -- AXI4-Stream Master Interface for Matrix C (64-bit)
        m_axis_c_tdata : out STD_LOGIC_VECTOR(63 downto 0);
        m_axis_c_tvalid : out STD_LOGIC;
        m_axis_c_tready : in STD_LOGIC;
        m_axis_c_tlast : out STD_LOGIC
    );
    end component;
    
    -- Test configuration (same as your other testbench)
    constant log2Acols : integer := 3;
    constant log2Brows : integer := 3;
    constant log2depth : integer := 4;
    constant dataWidthAB : integer := 8;
    constant dataWidthC : integer := 24;
    
    -- Calculate matrix dimensions  
    constant MATRIX_A_ELEMENTS : integer := 2**(log2Acols+log2depth); -- 2^(3+4) = 128
    constant MATRIX_B_ELEMENTS : integer := 2**(log2Brows+log2depth); -- 2^(3+4) = 128
    constant MATRIX_C_ELEMENTS : integer := 2**(log2Acols+log2Brows); -- 2^(3+3) = 64
    
    -- Clock and Reset
    signal aclk : STD_LOGIC;
    signal aresetn : STD_LOGIC;
    
    -- AXI4-Stream signals
    signal s_axis_tdata : STD_LOGIC_VECTOR(63 downto 0);
    signal s_axis_tvalid : STD_LOGIC := '0';
    signal s_axis_tready : STD_LOGIC;
    signal s_axis_tlast : STD_LOGIC := '0';
    
    signal m_axis_c_tdata : STD_LOGIC_VECTOR(63 downto 0);
    signal m_axis_c_tvalid : STD_LOGIC;
    signal m_axis_c_tready : STD_LOGIC := '1';
    signal m_axis_c_tlast : STD_LOGIC;
    
    -- Control signals
    signal reset : STD_LOGIC;
    signal counter : STD_LOGIC_VECTOR(log2Acols+log2depth downto 0);
    
    -- Signals for result readout
    type state_type is (LOADING, WAITING, READING, DONE);
    signal current_state : state_type := LOADING;
    signal read_counter : STD_LOGIC_VECTOR(log2Acols+log2Brows downto 0);
    signal matrix_complete : STD_LOGIC := '0';
    
    -- Array to store the result matrix for verification
    type result_matrix_type is array (0 to 2**(log2Acols+log2Brows)-1) of STD_LOGIC_VECTOR(dataWidthC-1 downto 0);
    signal result_matrix : result_matrix_type;

begin

    DUT_inst : matrix_core_axi_wrapper
    Generic map (log2Acols, log2Brows, log2depth, dataWidthAB, dataWidthC)
    Port map(aclk, aresetn, s_axis_tdata, s_axis_tvalid, s_axis_tready, s_axis_tlast,
             m_axis_c_tdata, m_axis_c_tvalid, m_axis_c_tready, m_axis_c_tlast);

    process begin
        aclk <= '0';
        wait for 5 ns;
        aclk <= '1';
        wait for 5 ns;
    end process;
    
    process begin
       reset <= '1';
       wait for 100 ns;
       reset <= '0';
       wait;
    end process;
    
    aresetn <= not reset;
    
    -- Combined process for sending and receiving data
    process(aclk) 
        variable a_val, b_val : STD_LOGIC_VECTOR(31 downto 0);
    begin
        if rising_edge(aclk) then
            if reset = '1' then
                counter <= (others => '0');
                s_axis_tvalid <= '0';
                s_axis_tlast <= '0';
                current_state <= LOADING;
                read_counter <= (others => '0');
                matrix_complete <= '0';
            else
                case current_state is
                    when LOADING =>
                        -- Send input data via AXI Stream
                        if conv_integer(counter) < MATRIX_A_ELEMENTS then
                            -- Prepare A and B values (exactly same as bram_dsp_mac_TB)
                            a_val := x"000000" & std_logic_vector(to_unsigned(conv_integer(counter) + 1, 8));  -- A values 1,2,3...
                            b_val := x"000000" & (x"40" - counter(7 downto 0)); -- B values 64,63,62... (same as direct testbench)
                            
                            -- Pack data: A[63:32] | B[31:0]
                            s_axis_tdata <= a_val & b_val;
                            s_axis_tvalid <= '1';
                            
                            -- Assert TLAST on final transfer
                            if conv_integer(counter) = MATRIX_A_ELEMENTS - 1 then
                                s_axis_tlast <= '1';
                            else
                                s_axis_tlast <= '0';
                            end if;
                            
                            -- Only increment counter when data is accepted
                            if s_axis_tready = '1' then
                                counter <= counter + 1;
                            end if;
                        else
                            s_axis_tvalid <= '0';
                            s_axis_tlast <= '0';
                            current_state <= WAITING;
                        end if;
                        
                    when WAITING =>
                        -- Wait for output to start
                        s_axis_tvalid <= '0';
                        s_axis_tlast <= '0';
                        
                        if m_axis_c_tvalid = '1' then
                            current_state <= READING;
                            read_counter <= (others => '0');
                        end if;
                        
                    when READING =>
                        -- Read output data
                        s_axis_tvalid <= '0';
                        s_axis_tlast <= '0';
                        m_axis_c_tready <= '1';
                        
                        if m_axis_c_tvalid = '1' and conv_integer(read_counter) < MATRIX_C_ELEMENTS then
                            -- Store the current output value (extract 24-bit result)
                            result_matrix(conv_integer(read_counter)) <= m_axis_c_tdata(dataWidthC-1 downto 0);
                            read_counter <= read_counter + 1;
                            
                            -- Check for completion
                            if m_axis_c_tlast = '1' or conv_integer(read_counter) = MATRIX_C_ELEMENTS - 1 then
                                current_state <= DONE;
                                matrix_complete <= '1';
                            end if;
                        end if;
                        
                    when DONE =>
                        -- Matrix readout complete
                        s_axis_tvalid <= '0';
                        s_axis_tlast <= '0';
                        m_axis_c_tready <= '1';
                        matrix_complete <= '1';
                end case;
            end if;
        end if;
    end process;
    
    -- Process to display the result matrix when complete
    process(matrix_complete)
        variable row, col : integer;
    begin
        if matrix_complete = '1' then
            report "Matrix multiplication result via AXI Wrapper:";
            report "Expected results (case 3):";
            report "   7408     5233     3058      883    33268    31349    29174    26999";
            report "  21880    15609     9338     3067    92796    90877    84606    78335";
            report "  36352    25985    15618     5251   152324   150405   140038   129671";
            report "  50824    36361    21898     7435   211852   209933   195470   181007";
            report "  65296    46737    28178     9619   271380   269461   250902   232343";
            report "  79768    57113    34458    11803   330908   328989   306334   283679";
            report "  94240    67489    40738    13987   390436   388517   361766   335015";
            report " 108712    77865    47018    16171   449964   448045   417198   386351";
            report "";
            report "Actual results from AXI wrapper:";
            for i in 0 to MATRIX_C_ELEMENTS-1 loop
                row := i / (2**log2Brows);
                col := i mod (2**log2Brows);
                if col = 0 then
                    report "Row " & integer'image(row) & ":";
                end if;
                report "  C[" & integer'image(row) & "][" & integer'image(col) & "] = " & 
                       integer'image(conv_integer(result_matrix(i)));
            end loop;
            
            report "=== AXI WRAPPER TEST COMPLETED ===";
        end if;
    end process;

end Behavioral;
