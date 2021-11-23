%% GAIT RECOGNITION BY ML ANALYSIS ON IMU DATA

clear ;
close all;
clc
addpath("include");

%% MACROS
NCOLUMNS = 150;
STARTING_FS = 100;

activities = ["PhaseONE","PhaseTWO","PhaseTHREE", "PhaseFOUR"];

features_avaiable = [
                       "MEAN"   ,...
                       "STD"    ,...
                       "MEDIAN" ,...
                       "VAR"    ,...
                       "RANGE"  ,...
                       "RMS"    ,...
                       "MODE"   ,...
                       "MAD"    ];


%% DATA IMPORTING
try
%     file1 = readtable("data/record_10-11-21_1st_random.csv", 'VariableNamingRule','preserve');
%     file2 = readtable("data/record_10-11-21_2nd_linAccZ.csv", 'VariableNamingRule','preserve');
    file1 = readtable("data/record_walk_21-11-21_1st_hips/record_walk_21-11-21_1st_hips.csv",'VariableNamingRule','preserve');
    file2 = readtable("data/record_walk_21-11-21_2nd_caviglia/record_walk_21-11-21_2nd_caviglia.csv",'VariableNamingRule','preserve');
    
    disp("Data successfully imported");
catch ME
    if strcmp(ME.identifier, 'MATLAB:textio:textio:FileNotFound')
        disp("ERROR: some data cannot be found");
        return;
    end
end


%% CREATION OF THE DATA STRUCTURE

dataset = {file1, file2};
[time, data] = mergeData(dataset);
disp("Dataset created");

%% DATA VISUALIZATION

dataToDisplay = 3;

yyaxis left, plot(time,data(:,dataToDisplay));
hold on
yyaxis right,plot(time,data(:,1));
set(gca, 'YTick', data(1,1):data(end,1));
hold off;

%% FFT CONVERSION
[xRange,dataFFT] = freqTransform(data, 0.5);

%% Plot
dataToDisplay = 3;

figure
plot(xRange, dataFFT(:,dataToDisplay));
xlabel('Frequency (Hz)')
ylabel('Magnitude')
title('Acceleration FFT')

%% MULTI-LAYER STRUCTURE
m = setMultiLayerStruct(data, NCOLUMNS);
disp("Multilayer structure created");

%% FEATURE MATRIX
n = extractFeatures(m);
disp("Feature matrix created");
