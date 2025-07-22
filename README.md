# Matrix Multiplier FPGA Implementation

## Overview
This project provides a high-performance VHDL implementation of a matrix multiplication accelerator designed for the Zynq UltraScale+ MPSoC platform, specifically targeting the ZCU104 evaluation board. The design leverages the Processing System (PS) and Programmable Logic (PL) integration to create an efficient hardware-software co-design solution for matrix operations.

**⚠️ WORK IN PROGRESS**: This project is currently under active development and debugging. The current focus is on implementing the block design to enable matrix data transfer and computation control from the SoC.

---

## Key Features
- **Hardware-Accelerated Matrix Multiplication:**  
  Custom VHDL implementation optimized for FPGA fabric with configurable matrix dimensions.

- **Zynq UltraScale+ Integration:**  
  Designed specifically for the ZCU104 board, utilizing the ARM Cortex-A53 processors and high-performance PL fabric.

- **SoC Communication Interface:**  
  Block design implementation for seamless data transfer between the Processing System and matrix multiplication core.

- **Parameterizable Design:**  
  Configurable matrix dimensions and data width through VHDL generics.

- **Comprehensive Verification:**  
  Test bench infrastructure for validation of matrix operations and system integration.

---

## Target Hardware
- **Development Board**: Xilinx ZCU104 Evaluation Board
- **SoC**: Zynq UltraScale+ MPSoC (XCZU7EV-2FFVC1156)
- **ARM Processors**: Quad-core ARM Cortex-A53 + Dual-core ARM Cortex-R5F
- **FPGA Fabric**: Kintex UltraScale+ with high-speed transceivers

---

## Project Structure
```
├── src/
│   ├── hdl/                    # VHDL source files
│   │   ├── matrix_core.vhd     # Core matrix multiplication engine
│   │   └── matrix_core_wrapper.vhd  # AXI wrapper for SoC integration
│   ├── sim/                    # Test bench files
│   │   ├── matrix_core_TB.vhd  # Core module test bench
│   │   └── matrix_core_wrapper_TB.vhd  # Wrapper test bench
│   ├── constraints/            # Timing and placement constraints
│   ├── ip/                     # Custom IP cores
│   └── repo/                   # IP repository
├── generate_project.tcl        # Vivado project generation script
├── README.md                   # Project documentation
└── LICENSE                     # License information
```

---

## Development Status

### Completed Components
- ✅ Core matrix multiplication VHDL module
- ✅ Basic test bench infrastructure
- ✅ Project structure and build scripts

### In Development
-  **Block Design Implementation**: Creating the Vivado block design for PS-PL integration
-  **AXI Interface**: Implementing AXI4-Lite/AXI4-Stream interfaces for data transfer
-  **SoC Software**: Developing ARM application for matrix data management
-  **Performance Optimization**: Fine-tuning the hardware implementation

### Planned Features
-  DMA integration for high-throughput data transfer
-  Multiple precision support (fixed-point, floating-point)
-  Streaming matrix operations
-  Power consumption analysis
-  Linux device driver integration

---

## Getting Started

### Prerequisites
- **Vivado Design Suite**: In my case was 2024.1
- **Hardware**: Zynq UltraScale+ (block design ongoing)

### Setup
1. Clone the repository:
   ```bash
   git clone https://github.com/MarcosG-Eng/Matrix_Multiplier.git
   cd Matrix_Multiplier
   ```

2. Open Vivado and source the project generation script:
   ```tcl
   source ./generate_project.tcl
   ```

3. Build the hardware design:
   - Synthesize and implement the design
   - Generate the bitstream
   - Export hardware for software development


## Usage

### Simulation
Run the provided test benches to verify functionality:
```tcl
# In Vivado TCL console
run_simulation -behavioral
```

### Hardware Testing
*Note: Hardware deployment procedures are being finalized as part of the ongoing development.*

---

## License
This project is licensed under the MIT License. See the `LICENSE` file for details.

---

## Contact
For questions, please open an issue on GitHub.

---

