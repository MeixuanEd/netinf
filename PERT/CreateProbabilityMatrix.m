function [AprobHist, pertOrders] = CreateProbabilityMatrix(observedData, pertIdx, obsIdx, pertTimes, ...
                                                        leftPad, rightPad, method, thresh, movvarWidth)
    % Check that all the necessary input arguments are specified.
    if nargin < 7
        error('Not enough input arguments.')
    end
    
    if nargin < 8
        movvarWidth = 0;
    end
    
    nvars = length(obsIdx);
    
    % Get the number of perturbations and the number
    % of observations.
    numPerts = length(pertIdx);
    
    % Find causal connections from perturbation data.
    % pertOrders will have dimension (numObs x nvars).
    pertOrders = GetPertOrders(observedData, pertIdx, obsIdx, pertTimes, leftPad, rightPad, method, thresh, movvarWidth);
    
    % Initialize the probability matrix we will construct.
    Aprob = nan(nvars, nvars);
    % Create a penalty factor that will multiplicatively decrease
    % probabilities of non-causal edges.
    penalty = 0.1;
    
    AprobHist = nan(nvars, nvars, numPerts);
    obsInds = find(obsIdx);
    for numPert=1:numPerts
        pertInd = pertIdx(numPert);
        
        % If the initially perturbed node in the cascade cannot be
        % observed, we can still find the nodes that it causes.
        if ~ismember(pertInd, find(obsIdx))
            Aprob(pertOrders(numPert, :) == 2, pertInd) = 1;
        end
        
        for j=obsInds
            for k=obsInds
                % j is the index causing and k is the index being caused.
                jPertOrder = pertOrders(numPert, j);
                kPertOrder = pertOrders(numPert, k);
                
                % If j never becomes perturbed, move on.
                if isinf(jPertOrder)
                    continue
                end
                
                % If the causal arrow from j to k has not been assigned a
                % probability yet, then assign it to the default 0.5.
                prevProb = 0.5;
                if ~isnan(Aprob(k, j))
                    prevProb = Aprob(k, j);
                end
                
                causalInds = pertOrders(numPert, :) == kPertOrder - 1;
                if ~isinf(kPertOrder) && causalInds(j)
                    % If j causes k, then recompute the probability of the
                    % edge j to k.
                    causalProbs = Aprob(k, causalInds);
                    causalProbs(isnan(causalProbs)) = 0.5;
                    Aprob(k, j) = prevProb / (1 - prod(1 - causalProbs));
                else
                    % If we have evidence that j was perturbed and k did
                    % not become perturbed immediately after, then penalize this edge.
                    if (jPertOrder < kPertOrder - 1)
                        Aprob(k, j) = penalty * prevProb;
                    end
                end
            end
        end
        
        AprobHist(:, :, numPert) = Aprob;
    end
end
