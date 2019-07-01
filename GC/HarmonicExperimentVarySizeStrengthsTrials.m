clear all; close all; clc;
run '../mvgc_v1.0/startup.m'
addpath('../DataScripts')
addpath('../DataScripts/SimulateData')
addpath('../DataScripts/SimulateData/InitFunctions')

expNum = 'VarySizeStrengthsTrials';

networkSizes = [2, 5, 10, 15, 20];
numSizes = length(networkSizes);

strengths = [1, 2, 5, 10, 50];
numStrengths = length(strengths);

trialsList = [1, 10, 25, 50, 100];
trialsListLength = length(trialsList);

% Initialize masses, positions, and velocities of oscillators.
mfn = @(n) constfn(n, 1);
pfn = @(n) randfn(n, -0.5, 0.5);
vfn = @(n) zeros([n, 1]);

% Specify the damping constant.
damping = 0.2;
cfn = @(n) constfn(n, damping);

% Define time sampling.
deltat = 0.1; % space between time points
endtime = 25;
nobs = round(endtime / deltat); % number of time points (observations)
tSpan = linspace(0, endtime, nobs);

% Specify noise and prepocessing for data.
measParam = 0.1;
noisefn  = @(data) WhiteGaussianNoise(data, measParam);

% Specify boundary conditions.
bc = 'fixed';

% Probabilities of network connections.
prob = 0.5;

% Number of matrices to average results over.
numMats = 100;

preprocfn = @(data) standardize(data);

% Spectral radius threshold for MVGC toolbox.
rhoThresh = 0.995;


% Check that directory with experiment data exists
expName = sprintf('EXP%s', expNum);
expPath = sprintf('../HarmonicExperiments/%s', expName);
if exist(expPath, 'dir') == 7
    m=input(sprintf('%s\n already exists, would you like to continue and overwrite this data (Y/N): ', expPath),'s');
    if upper(m) == 'N'
        return
    end
    rmdir(expPath, 's')
end
mkdir(expPath)

% Save experiment parameters.
save(sprintf('%s/params.mat', expPath));

% Make directory to hold result files if one does not already exist
resultPath = sprintf('%s/GCResults', expPath);
if exist(resultPath, 'dir') == 7
    m=input(sprintf('%s\n already exists, would you like to continue and overwrite these results (Y/N): ', resultPath),'s');
    if upper(m) == 'N'
       return
    end
    rmdir(resultPath, 's')
end
mkdir(resultPath)


%% Generate Data and Run Granger Causality Experiments

predMats = cell(1, numSizes * numStrengths * trialsListLength * numMats);
tprLog = nan(1, numSizes * numStrengths * trialsListLength * numMats);
fprLog = nan(1, numSizes * numStrengths * trialsListLength * numMats);
accLog = nan(1, numSizes * numStrengths * trialsListLength * numMats);
numRerun = zeros(1, numSizes * numStrengths * trialsListLength * numMats);
diagnosticsLog = nan(numSizes * numStrengths * trialsListLength * numMats, 3);

parsave = @(fname, noisyData, mat, K)...
            save(fname, 'noisyData', 'mat', 'K');

% Number of parallel processes
M = 12;
c = progress(numSizes * numStrengths * trialsListLength * numMats);
for idx = 1 : numSizes * numStrengths * trialsListLength * numMats %parfor (idx = 1 : numSizes * numStrengths * trialsListLength * numMats, M)
    [j, k, l, m] = ind2sub([numSizes, numStrengths, trialsListLength, numMats], idx);
    fprintf('size: %d, strength: %d, trials: %d\n', j, k, l)
    
    currExpPath = sprintf('%s/size%d/strength%d/trials%d/mat%d', expPath, j, k, l, m);
    if exist(sprintf('%s/dataLog.mat', currExpPath), 'file') ~= 2
        mkdir(currExpPath)
    else
        continue
    end
    
    % Count the number of iterations done by the parfor loop
    c.count();
    
    nvars = networkSizes(j);
    strength = strengths(k);
    numTrials = trialsList(l);
    
    while true
        % Create adjacency matrices.
        mat = MakeNetworkER(nvars, prob, true);
        K = MakeNetworkTriDiag(nvars+2, false);
        K(2:nvars+1, 2:nvars+1) = mat;
        K = strength * K;
        
        % If any nodes in the network are not connected to the walls or
        % the eigenvalues of the system have positive real parts, don't
        % use this network.
        [~, amplitudes] = checkHarmonicMat(K, damping);
        if any(amplitudes > 0)
            numRerun(idx) = numRerun(idx) + 1;
            continue
        end
        
        % Specify forcing function for oscillators.
        forcingFunc = zeros([nvars, nobs]);

        % Simulate oscillator trajectories.
        data = GenerateHarmonicData(nvars, tSpan, ...
                numTrials, K, pfn, vfn, mfn, cfn, bc, forcingFunc);
        noisyData = noisefn(data);

        dataObsIdx = true([1, nvars]); % default parameter
        [est, tableResults] = GrangerBaseExperiment(noisyData, ...
                mat, preprocfn, dataObsIdx, rhoThresh);
        if isnan(est)
            numRerun(idx) = numRerun(idx) + 1;
            continue
        end
        
        parsave(sprintf('%s/dataLog.mat', currExpPath), noisyData, mat, K);
        
        predMats{idx} = est;
        tprLog(idx) = tableResults.tpr;
        fprLog(idx) = tableResults.fpr;
        accLog(idx) = tableResults.acc;
        diagnosticsLog(idx, :) = tableResults.diagnostics;
        break
    end
end

% Reshape data structures
predMats = reshape(predMats, numSizes, numStrengths, trialsListLength, numMats);
tprLog = reshape(tprLog, [numSizes, numStrengths, trialsListLength, numMats]);
fprLog = reshape(fprLog, [numSizes, numStrengths, trialsListLength, numMats]);
accLog = reshape(accLog, [numSizes, numStrengths, trialsListLength, numMats]);
diagnosticsLog = reshape(diagnosticsLog, [numSizes, numStrengths, trialsListLength, numMats, 3]);
numRerun = sum(reshape(numRerun, [numSizes, numStrengths, trialsListLength, numMats]), 4);

% Save experiment results
save(sprintf('%s/predMats.mat', resultPath), 'predMats');
save(sprintf('%s/tprLog.mat', resultPath), 'tprLog');
save(sprintf('%s/fprLog.mat', resultPath), 'fprLog');
save(sprintf('%s/accLog.mat', resultPath), 'accLog');
save(sprintf('%s/diagnosticsLog.mat', resultPath), 'diagnosticsLog');
save(sprintf('%s/numRerun.mat', resultPath), 'numRerun');


%% Plot Results

trialsInd = 1;

% Show number of simulations that were skipped.
figure(1)
imagesc(reshape(numRerun(:, :, trialsInd), [numSizes, numStrengths]))
set(gca,'YDir','normal')
colormap jet
colorbar
title('Number of Simulations Rerun by Our Analysis')
xlabel('Connection Strength')
ylabel('Network Size')
set(gca, 'XTick', strengths)
set(gca, 'YTick', networkSizes)
%set(gca,'TickLength', [0 0])


% Show average accuracies for each number of perturbations and
% observations.
aveAccuracies = nanmean(accLog, 4);
figure(2)
clims = [0, 1];
imagesc(reshape(aveAccuracies(:, :, trialsInd), [numSizes, numStrengths]), clims)
set(gca,'YDir','normal')
%set(gca, 'XTick', [])
%set(gca, 'YTick', [])
colormap jet
colorbar
title('Average Accuracy over Simulations')
xlabel('Connection Strength')
ylabel('Network Size')
set(gca, 'XTick', strengths)
set(gca, 'YTick', networkSizes)
%set(gca, 'TickLength', [0 0])


% Show average TPR for each number of perturbations and
% observations.
aveTPR = nanmean(tprLog, 4);
figure(3)
clims = [0, 1];
imagesc(reshape(aveTPR(:, :, trialsInd), [numSizes, numStrengths]), clims)
set(gca,'YDir','normal')
%set(gca, 'XTick', [])
%set(gca, 'YTick', [])
colormap jet
colorbar
title('Average TPR over Simulations')
xlabel('Connection Strength')
ylabel('Network Size')
set(gca, 'XTick', strengths)
set(gca, 'YTick', networkSizes)
%set(gca, 'TickLength', [0 0])


% Show average FPR for each number of perturbations and
% observations.
aveFPR = nanmean(fprLog, 4);
figure(4)
clims = [0, 1];
imagesc(reshape(aveFPR(:, :, trialsInd), [numSizes, numStrengths]), clims)
set(gca,'YDir','normal')
%set(gca, 'XTick', [])
%set(gca, 'YTick', [])
colormap jet
colorbar
title('Average FPR over Simulations')
xlabel('Connection Strength')
ylabel('Network Size')
set(gca, 'XTick', strengths)
set(gca, 'YTick', networkSizes)
%set(gca, 'TickLength', [0 0])
