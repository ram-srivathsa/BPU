# BPU
Combining the Branch predictor and the BTB into a Branch Prediction Unit

Author:Ram Srivathsa Sankar
Mentor:Rahul Bodduna

The 'bpu' folder contains the .bsv files for the bpu, predictor and btb. The 'Testbench' folder contains the .bsv file for the testbench as well as the necessary .dump and .bin files for testing the Dhrystone benchmark. 

The 'verilog' folder contains the necessary .v files for Vivado synthesis while the 'vivado' folder contains the Vivado project file as well the area and timing reports.

Results:

On testing with Dhrystone trace, 110 mispredictions were reported out of 58800 total branches while 18 mispredictions were reported for the first 1000 branches which corresponds to prediction accuracies of 99.8% and 98.2% respectively.

In Vivado, the design was found to have a maximum operating frequency of 285MHz and occupies 589 LUTs on an Artix 7 board. The detailed reports may be found in the 'vivado' folder.
