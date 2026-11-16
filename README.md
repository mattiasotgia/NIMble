# NIMble: a modest FPGA-based replacement for a NIM coincidence setup

## Repository structure

This repository contains all the FPGA control code, simulation, DAQ scripts to be able to setup the module and operate it in the laboratory. 

The code is structured as follows

```
./
├── setup.sh
├── bin
├── daq
└── src
```

Under `src` is the VerilogHDL` content, used to program and simulate the FPGA controller. 

The `daq` directory contains the I/O code to interface the controller with a receiving computer, and provides a few DAQ utilities and live data monitoring. 

Sourcing the `setup.sh` file will setup the repository for development only. The scripts for setting up the DAQ envronment or the FPGA deployment are under the `bin` directory

## Usage

## Requirements

## Changelog
