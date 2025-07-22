library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

entity matrix_core_axi_wrapper is
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
        m_axis_c_tlast : out STD_LOGIC;
        
        -- Debug signals for ILA
        debug_cReady_out : out STD_LOGIC;
        debug_readC_in : out STD_LOGIC;
        debug_c_out : out STD_LOGIC_VECTOR(dataWidthC-1 downto 0);
        
        -- RAM access debug signals (observe the actual RAM operations)
        debug_validA_in : out STD_LOGIC;
        debug_validB_in : out STD_LOGIC;
        debug_validC_in : out STD_LOGIC;
        debug_addrA_in : out STD_LOGIC_VECTOR(log2Acols+log2depth-1 downto 0);
        debug_addrB_in : out STD_LOGIC_VECTOR(log2Brows+log2depth-1 downto 0);
        debug_addrC_in : out STD_LOGIC_VECTOR(log2Acols+log2Brows-1 downto 0);
        debug_a_in : out STD_LOGIC_VECTOR(dataWidthAB-1 downto 0);
        debug_b_in : out STD_LOGIC_VECTOR(dataWidthAB-1 downto 0);
        debug_c_in : out STD_LOGIC_VECTOR(dataWidthC-1 downto 0);
        debug_current_state : out STD_LOGIC_VECTOR(1 downto 0)
    );
end matrix_core_axi_wrapper;

architecture Behavioral of matrix_core_axi_wrapper is

    -- Matrix Core Component Declaration
    component matrix_core is
        Generic (
            log2Acols : integer;
            log2Brows : integer;
            log2depth : integer;
            dataWidthAB : integer;
            dataWidthC : integer
        );
        Port (
            clock : in STD_LOGIC;
            load_in, validA_in, validB_in, validC_in : in STD_LOGIC;
            addrA_in : in STD_LOGIC_VECTOR(log2Acols+log2depth-1 downto 0);
            addrB_in : in STD_LOGIC_VECTOR(log2Brows+log2depth-1 downto 0);
            addrC_in : in STD_LOGIC_VECTOR(log2Acols+log2Brows-1 downto 0);
            a_in : in STD_LOGIC_VECTOR (dataWidthAB-1 downto 0);
            b_in : in STD_LOGIC_VECTOR (dataWidthAB-1 downto 0);
            c_in : in STD_LOGIC_VECTOR (dataWidthC-1 downto 0);
            cReady_out : out STD_LOGIC;
            readC_in : in STD_LOGIC;
            c_out : out STD_LOGIC_VECTOR (dataWidthC-1 downto 0)
        );
    end component;

    -- State Machine
    type state_type is (IDLE, LOADING_DATA, COMPUTING, READING_C);
    signal current_state : state_type := IDLE;
    
    -- Matrix Core Signals
    signal load_in, validA_in, validB_in, validC_in : STD_LOGIC := '0';
    signal addrA_in : STD_LOGIC_VECTOR(log2Acols+log2depth-1 downto 0);
    signal addrB_in : STD_LOGIC_VECTOR(log2Brows+log2depth-1 downto 0);
    signal addrC_in : STD_LOGIC_VECTOR(log2Acols+log2Brows-1 downto 0);
    signal a_in : STD_LOGIC_VECTOR(dataWidthAB-1 downto 0);
    signal b_in : STD_LOGIC_VECTOR(dataWidthAB-1 downto 0);
    signal c_in : STD_LOGIC_VECTOR(dataWidthC-1 downto 0);
    signal cReady_out : STD_LOGIC;
    signal readC_in : STD_LOGIC := '0';
    signal c_out : STD_LOGIC_VECTOR(dataWidthC-1 downto 0);
    
    -- AXI Signal decomposition
    -- Input: tdata[63:32] = Matrix A data, tdata[31:0] = Matrix B data
    signal data_a_from_stream : STD_LOGIC_VECTOR(dataWidthAB-1 downto 0);
    signal data_b_from_stream : STD_LOGIC_VECTOR(dataWidthAB-1 downto 0);
    
    -- Address auto-generation counters
    signal addr_counter : STD_LOGIC_VECTOR(log2Acols+log2depth-1 downto 0);  -- Single counter like direct testbench
    signal addr_counter_C : STD_LOGIC_VECTOR(log2Acols+log2Brows-1 downto 0);
    
    -- Control signals for AXI interfaces
    signal s_axis_tready_int : STD_LOGIC := '0';
    signal m_axis_c_tvalid_int : STD_LOGIC := '0';
    signal m_axis_c_tlast_int : STD_LOGIC := '0';
    
    -- Constants for matrix sizes (must be declared first)
    constant MATRIX_A_SIZE : integer := 2**(log2Acols+log2depth);
    constant MATRIX_B_SIZE : integer := 2**(log2Brows+log2depth);
    constant MATRIX_C_SIZE : integer := 2**(log2Acols+log2Brows);
    constant MAX_ELEMENTS : integer := MATRIX_A_SIZE; -- A and B should have same element count for simultaneous loading

    -- Delayed signals for proper read timing (1 cycle delay for RAM read)
    signal addr_counter_C_delayed : STD_LOGIC_VECTOR(log2Acols+log2Brows-1 downto 0);
    signal read_valid_delayed : STD_LOGIC := '0';
    
    -- Counter for read cycles
    signal read_counter : integer range 0 to MATRIX_C_SIZE + 10;
    signal next_read_counter : integer range 0 to MATRIX_C_SIZE + 10;
    
    -- Element counters for loading phase
    signal elements_loaded : integer range 0 to 2**(log2Acols+log2depth);

begin

    -- Matrix Core Instance
    matrix_core_inst : matrix_core
        Generic map (
            log2Acols => log2Acols,
            log2Brows => log2Brows,
            log2depth => log2depth,
            dataWidthAB => dataWidthAB,
            dataWidthC => dataWidthC
        )
        Port map (
            clock => aclk,
            load_in => load_in,
            validA_in => validA_in,
            validB_in => validB_in,
            validC_in => validC_in,
            addrA_in => addrA_in,
            addrB_in => addrB_in,
            addrC_in => addrC_in,
            a_in => a_in,
            b_in => b_in,
            c_in => c_in,
            cReady_out => cReady_out,
            readC_in => readC_in,
            c_out => c_out
        );

    -- AXI Signal Assignments
    s_axis_tready <= s_axis_tready_int;
    m_axis_c_tvalid <= m_axis_c_tvalid_int;
    m_axis_c_tlast <= m_axis_c_tlast_int;
    
    -- Decompose AXI input data (64-bit)
    -- Matrix A: tdata[63:32] (use lower 8 bits for data)
    data_a_from_stream <= s_axis_tdata(32+dataWidthAB-1 downto 32);
    
    -- Matrix B: tdata[31:0] (use lower 8 bits for data)
    data_b_from_stream <= s_axis_tdata(dataWidthAB-1 downto 0);
    
    -- Compose AXI output data (64-bit)
    -- Matrix C: Put result in lower bits, pad upper bits with zeros
    m_axis_c_tdata <= std_logic_vector(resize(unsigned(c_out), 64));
    
    -- Main Control Process
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                -- Reset all signals
                current_state <= IDLE;
                addr_counter <= (others => '0');
                addr_counter_C <= (others => '0');
                elements_loaded <= 0;
                
                load_in <= '0';
                validA_in <= '0';
                validB_in <= '0';
                validC_in <= '0';
                readC_in <= '0';
                
                s_axis_tready_int <= '0';
                m_axis_c_tvalid_int <= '0';
                m_axis_c_tlast_int <= '0';
                
                -- Initialize delayed signals
                addr_counter_C_delayed <= (others => '0');
                read_valid_delayed <= '0';
                read_counter <= 0;
                next_read_counter <= 1;
                
            else
                case current_state is
                    when IDLE =>
                        -- Ready to receive data (auto-start when data arrives)
                        s_axis_tready_int <= '1';
                        m_axis_c_tvalid_int <= '0';
                        m_axis_c_tlast_int <= '0';
                        
                        load_in <= '0';
                        validA_in <= '0';
                        validB_in <= '0';
                        validC_in <= '0';
                        readC_in <= '0';
                        
                        -- Reset counters for new transaction
                        addr_counter <= (others => '0');
                        addr_counter_C <= (others => '0');
                        elements_loaded <= 0;
                        read_counter <= 0;
                        next_read_counter <= 1;
                        
                        -- Auto-start when valid AXI data arrives
                        if s_axis_tvalid = '1' and s_axis_tready_int = '1' then
                            current_state <= LOADING_DATA;
                        end if;
                        
                    when LOADING_DATA =>
                        -- Load Matrix A and B elements simultaneously
                        if s_axis_tvalid = '1' and s_axis_tready_int = '1' then
                            -- Load Matrix A element
                            a_in <= data_a_from_stream;
                            addrA_in <= addr_counter;  -- Use same counter for both A and B like direct testbench
                            validA_in <= '1';
                            
                            -- Load Matrix B element  
                            b_in <= data_b_from_stream;
                            addrB_in <= addr_counter;  -- Use same counter for both A and B like direct testbench
                            validB_in <= '1';
                            
                            -- Initialize C matrix with counter value (exactly like direct testbench)
                            c_in <= std_logic_vector(resize(unsigned(addr_counter), dataWidthC));  -- Convert addr_counter to 24-bit
                            addrC_in <= addr_counter(log2Acols+log2Brows-1 downto 0); -- Use same counter for C addressing
                            validC_in <= '1';
                            
                            load_in <= '1';
                            
                            -- Increment single address counter (like direct testbench)
                            addr_counter <= addr_counter + 1;
                            elements_loaded <= elements_loaded + 1;
                            
                            -- Check for end of transfer
                            if s_axis_tlast = '1' then
                                current_state <= COMPUTING;
                                s_axis_tready_int <= '0';
                            end if;
                        else
                            -- No valid data this cycle
                            validA_in <= '0';
                            validB_in <= '0';
                            validC_in <= '0';
                            load_in <= '0';
                        end if;
                        
                    when COMPUTING =>
                        -- Wait for matrix multiplication to complete
                        s_axis_tready_int <= '0';
                        load_in <= '0';
                        validA_in <= '0';
                        validB_in <= '0';
                        validC_in <= '0';
                        readC_in <= '0';
                        
                        if cReady_out = '1' then
                            current_state <= READING_C;
                            addr_counter_C <= (others => '0');
                            readC_in <= '1';
                            read_counter <= 0;
                            next_read_counter <= 1;
                            -- Pre-set the first address (this cycle), data will be ready next cycle
                            addrC_in <= (others => '0');
                            read_valid_delayed <= '0';  -- First valid will be delayed by 1 cycle
                        end if;
                        
                    when READING_C =>
                        -- Send Matrix C elements via AXI4-Stream
                        readC_in <= '1';
                        
                        -- Set address for current cycle
                        addrC_in <= addr_counter_C;
                        
                        -- Increment counters 
                        if m_axis_c_tready = '1' then
                            read_counter <= next_read_counter;
                            next_read_counter <= next_read_counter + 1;
                            addr_counter_C <= addr_counter_C + 1;
                        end if;
                        
                        -- Use next_read_counter to determine if we should send valid data
                        -- This way we look ahead to see if NEXT cycle will be valid
                        if next_read_counter >= 4 and next_read_counter < MATRIX_C_SIZE + 4 then
                            m_axis_c_tvalid_int <= '1';
                            
                            -- Set TLAST on the last valid element
                            if next_read_counter = MATRIX_C_SIZE + 4 - 1 then
                                m_axis_c_tlast_int <= '1';
                            else
                                m_axis_c_tlast_int <= '0';
                            end if;
                        else
                            m_axis_c_tvalid_int <= '0';
                            m_axis_c_tlast_int <= '0';
                        end if;
                        
                        -- Check for completion
                        if next_read_counter >= MATRIX_C_SIZE + 4 then
                            current_state <= IDLE;
                            readC_in <= '0';
                            m_axis_c_tvalid_int <= '0';
                            m_axis_c_tlast_int <= '0';
                        end if;
                        
                end case;
            end if;
        end if;
    end process;

    -- Debug signal assignments for ILA
    debug_cReady_out <= cReady_out;
    debug_readC_in <= readC_in;
    debug_c_out <= c_out;
    
    -- RAM access debug signals
    debug_validA_in <= validA_in;
    debug_validB_in <= validB_in;
    debug_validC_in <= validC_in;
    debug_addrA_in <= addrA_in;
    debug_addrB_in <= addrB_in;
    debug_addrC_in <= addrC_in;
    debug_a_in <= a_in;
    debug_b_in <= b_in;
    debug_c_in <= c_in;
    
    -- State machine debug (encode state as 2-bit vector)
    debug_current_state <= "00" when current_state = IDLE else
                          "01" when current_state = LOADING_DATA else
                          "10" when current_state = COMPUTING else
                          "11" when current_state = READING_C;

end Behavioral;
