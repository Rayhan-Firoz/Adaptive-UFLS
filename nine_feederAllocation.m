function feeder = nine_feederAllocation(data,op,Ybus,bus,freq)

% MODULE 9
% FEEDER-LEVEL LOAD SHEDDING ALLOCATION
%
% This module converts the bus shedding requirement from
% Module 8 into actual feeder shedding.
%
% MAIN RULES:
%   1. Feeders are shed as complete blocks.
%   2. Partial feeder shedding is NOT allowed.
%   3. Normal feeder load is used first.
%   4. Critical feeder load is used only as a fallback.
%   5. FVSI is taken from Module 8.
%   6. Frequency severity is taken from Module 5.
%
% STAGE 1:
%   Use normal feeders at the required buses.
%
% STAGE 2:
%   Use unused normal feeders in the same zone.
%   If necessary, use the closest larger normal feeder.
%
% STAGE 3:
%   Use critical feeder blocks for the remaining system
%   requirement.
%
% The input "result" from Newton-Raphson is not needed here.
% Ybus is only used for the final post-shedding NR check.

%% =========================================================
% 1. BASIC VALUES
% ==========================================================

Sbase = data.Sbase;

nBus = length(data.bus);

nFeeder = data.nFeeder;

tolerance = 1e-9;

allocationTolerance = 0.05;

maxCriticalOvershoot = 5;

%% =========================================================
% 2. CHECK INPUT DATA
% ==========================================================

if ~isfield(data,'bus')

    error('Module 9: data.bus is missing.');

end

if ~isfield(data,'Sbase')

    error('Module 9: data.Sbase is missing.');

end

if ~isfield(data,'nFeeder')

    error('Module 9: data.nFeeder is missing.');

end

if ~isfield(op,'feederLoad_MW')

    error('Module 9: op.feederLoad_MW is missing.');

end

if ~isfield(op,'feederNonShedable_MW')

    error('Module 9: op.feederNonShedable_MW is missing.');

end

if ~isfield(op,'feederNormalShedable_MW')

    error('Module 9: op.feederNormalShedable_MW is missing.');

end

if ~isfield(data,'feederSourceBus')

    error('Module 9: data.feederSourceBus is missing.');

end

if ~isfield(data,'feederStatus')

    error('Module 9: data.feederStatus is missing.');

end

%% =========================================================
% 3. CHECK MODULE 8 RESULTS
% ==========================================================

if ~isfield(bus,'Pshed_MW')

    error('Module 9: bus.Pshed_MW was not found.');

end

if ~isfield(bus,'fvsiRank')

    error('Module 9: bus.fvsiRank was not found.');

end

if ~isfield(bus,'zoneID')

    error('Module 9: bus.zoneID was not found.');

end

%% =========================================================
% 4. FEEDER DATA
% ==========================================================

feeder.id = (1:nFeeder)';

feeder.sourceBus = ...
    data.feederSourceBus(:);

feeder.status = ...
    data.feederStatus(:);

feeder.load_MW = ...
    max(op.feederLoad_MW(:),0);

feeder.nonShedable_MW = ...
    max(op.feederNonShedable_MW(:),0);

feeder.normalShedable_MW = ...
    max(op.feederNormalShedable_MW(:),0);

%% =========================================================
% 5. FEEDER ID
% ==========================================================

if isfield(data,'feederID')

    feeder.feederID = data.feederID;

else

    feeder.feederID = cell(nFeeder,1);

    for k = 1:nFeeder

        feeder.feederID{k} = ...
            sprintf('F%d',k);

    end

end

%% =========================================================
% 6. CHECK FEEDER DATA LENGTH
% ==========================================================

if length(feeder.sourceBus) ~= nFeeder

    error('Module 9: feeder source bus length is incorrect.');

end

if length(feeder.status) ~= nFeeder

    error('Module 9: feeder status length is incorrect.');

end

if length(feeder.load_MW) ~= nFeeder

    error('Module 9: feeder load length is incorrect.');

end

%% =========================================================
% 7. CHECK FEEDER LOAD
% ==========================================================

for k = 1:nFeeder

    feederTotal = ...
        feeder.nonShedable_MW(k) + ...
        feeder.normalShedable_MW(k);

    if abs(feederTotal - feeder.load_MW(k)) > 1e-6

        error(['Module 9: feeder load is inconsistent ' ...
               'for feeder %d.'],k);

    end

end

%% =========================================================
% 8. INITIALIZE SHEDDING RESULTS
% ==========================================================

feeder.PshedNormal_MW = ...
    zeros(nFeeder,1);

feeder.PshedCritical_MW = ...
    zeros(nFeeder,1);

feeder.Pshed_MW = ...
    zeros(nFeeder,1);

feeder.selectedNormal = ...
    false(nFeeder,1);

feeder.selectedCritical = ...
    false(nFeeder,1);

feeder.selected = ...
    false(nFeeder,1);

%% =========================================================
% 9. FIND ZONE OF EACH FEEDER
% ==========================================================

feeder.zoneID = zeros(nFeeder,1);

for k = 1:nFeeder

    sourceBus = feeder.sourceBus(k);

    busNumber = ...
        find(data.bus == sourceBus,1);

    if isempty(busNumber)

        error(['Module 9: feeder %d uses Bus %d, ' ...
               'but this bus was not found.'], ...
               k,sourceBus);

    end

    feeder.zoneID(k) = ...
        bus.zoneID(busNumber);

end

%% =========================================================
% 10. GET ZONE INFORMATION
% ==========================================================

zoneID = unique(bus.zoneID,'stable');

nZone = length(zoneID);

%% =========================================================
% 11. GET REQUIRED SHEDDING FROM MODULE 8
% ==========================================================

% Module 8 gives the required shedding at each bus.

busRequired_MW = ...
    bus.Pshed_MW(:);

%% =========================================================
% 12. CALCULATE ZONE REQUIREMENTS
% ==========================================================

feeder.zoneRequired_MW = ...
    zeros(nZone,1);

for z = 1:nZone

    currentZone = zoneID(z);

    buses = ...
        find(bus.zoneID == currentZone);

    feeder.zoneRequired_MW(z) = ...
        sum(busRequired_MW(buses));

end

%% =========================================================
% 13. GET ZONE FREQUENCY SEVERITY
% ==========================================================

zoneSeverity = ...
    zeros(nZone,1);

for z = 1:nZone

    currentZone = zoneID(z);

    found = false;

    if ~isempty(freq)

        if isfield(freq,'zoneID') && ...
                isfield(freq,'zoneFrequencyDeclineRate')

            for k = 1:length(freq.zoneID)

                if freq.zoneID(k) == currentZone

                    rate = ...
                        freq.zoneFrequencyDeclineRate(k);

                    if isfinite(rate)

                        zoneSeverity(z) = abs(rate);

                        found = true;

                    end

                    break;

                end

            end

        end

    end

    if found == false

        zoneSeverity(z) = 0;

    end

end

%% =========================================================
% 14. ORDER ZONES BY FREQUENCY SEVERITY
% ==========================================================

[~,zoneOrder] = ...
    sort(zoneSeverity,'descend');

feeder.zoneSeverity = ...
    zoneSeverity;

feeder.zoneSeverityOrder = ...
    zoneID(zoneOrder);

%% =========================================================
% 15. FIND BUS ORDER USING FVSI RANK
% ==========================================================

zoneBuses = cell(nZone,1);

for z = 1:nZone

    currentZone = zoneID(z);

    buses = ...
        find(bus.zoneID == currentZone);

    if isempty(buses)

        zoneBuses{z} = [];

        continue;

    end

    rank = ...
        bus.fvsiRank(buses);

    % Invalid ranks are placed at the end.

    for k = 1:length(rank)

        if ~isfinite(rank(k)) || rank(k) <= 0

            rank(k) = 999999;

        end

    end

    [~,order] = ...
        sort(rank,'ascend');

    zoneBuses{z} = ...
        buses(order);

end

%% =========================================================
% 16. INITIALIZE BUS RESULTS
% ==========================================================

feeder.busShedNormal_MW = ...
    zeros(nBus,1);

feeder.busShedCritical_MW = ...
    zeros(nBus,1);

feeder.busShed_MW = ...
    zeros(nBus,1);

feeder.busResidual_MW = ...
    busRequired_MW;

%% =========================================================
% 17. INITIALIZE ZONE RESULTS
% ==========================================================

feeder.zoneNormalShed_MW = ...
    zeros(nZone,1);

feeder.zoneCriticalShed_MW = ...
    zeros(nZone,1);

feeder.zoneActualShed_MW = ...
    zeros(nZone,1);

feeder.zoneResidual_MW = ...
    feeder.zoneRequired_MW;

%% =========================================================
% 18. STAGE 1
% NORMAL FEEDERS AT THE REQUIRED BUS
% ==========================================================

fprintf('\n');
fprintf('=============================================\n');
fprintf(' MODULE 9: FEEDER ALLOCATION\n');
fprintf('=============================================\n');

fprintf('\n');
fprintf('STAGE 1: NORMAL FEEDERS\n');
fprintf('---------------------------------------------\n');

for zz = 1:nZone

    z = zoneOrder(zz);

    currentZone = zoneID(z);

    buses = ...
        zoneBuses{z};

    % Residual can move to another bus in the
    % same zone.

    carriedResidual = 0;

    for bb = 1:length(buses)

        b = buses(bb);

        requirement = ...
            busRequired_MW(b) + ...
            carriedResidual;

        if requirement <= tolerance

            carriedResidual = 0;

            continue;

        end

        sourceBus = ...
            data.bus(b);

        %% -------------------------------------------------
        % Find unused normal feeders at this bus
        % --------------------------------------------------

        candidate = find( ...
            feeder.sourceBus == sourceBus & ...
            feeder.status == 1 & ...
            feeder.selectedNormal == false & ...
            feeder.normalShedable_MW > tolerance);

        if isempty(candidate)

            carriedResidual = requirement;

            continue;

        end

        %% -------------------------------------------------
        % Try to find a combination without overshoot
        % --------------------------------------------------

        capacities = ...
            feeder.normalShedable_MW(candidate);

        [chosen,chosenMW] = ...
            findNormalCombination( ...
            capacities,requirement);

        if isempty(chosen)

            carriedResidual = requirement;

            continue;

        end

        %% -------------------------------------------------
        % Select complete feeders
        % --------------------------------------------------

        actualShed = 0;

        for k = 1:length(chosen)

            feederNumber = ...
                candidate(chosen(k));

            shedMW = ...
                feeder.normalShedable_MW(feederNumber);

            feeder.PshedNormal_MW(feederNumber) = ...
                shedMW;

            feeder.Pshed_MW(feederNumber) = ...
                shedMW;

            feeder.selectedNormal(feederNumber) = true;

            feeder.selected(feederNumber) = true;

            actualShed = ...
                actualShed + shedMW;

        end

        feeder.busShedNormal_MW(b) = ...
            feeder.busShedNormal_MW(b) + ...
            actualShed;

        feeder.busShed_MW(b) = ...
            feeder.busShed_MW(b) + ...
            actualShed;

        carriedResidual = ...
            max(requirement - actualShed,0);

    end

end

%% =========================================================
% 19. UPDATE ZONE RESULTS
% ==========================================================

for z = 1:nZone

    currentZone = zoneID(z);

    buses = ...
        find(bus.zoneID == currentZone);

    feeder.zoneNormalShed_MW(z) = ...
        sum(feeder.busShedNormal_MW(buses));

    feeder.zoneResidual_MW(z) = ...
        max( ...
        feeder.zoneRequired_MW(z) - ...
        feeder.zoneNormalShed_MW(z), ...
        0);

end

%% =========================================================
% 20. STAGE 2
% UNUSED NORMAL FEEDERS IN SAME ZONE
% ==========================================================

fprintf('\n');
fprintf('STAGE 2: NORMAL FEEDER CLEANUP\n');
fprintf('---------------------------------------------\n');

maxRounds = 5;

for round = 1:maxRounds

    totalResidualBefore = ...
        sum(feeder.zoneResidual_MW);

    if totalResidualBefore <= allocationTolerance

        break;

    end

    improvement = 0;

    for zz = 1:nZone

        z = zoneOrder(zz);

        currentZone = zoneID(z);

        zoneResidual = ...
            feeder.zoneResidual_MW(z);

        if zoneResidual <= tolerance

            continue;

        end

        %% -------------------------------------------------
        % Find unused normal feeders in this zone
        % --------------------------------------------------

        candidate = find( ...
            feeder.zoneID == currentZone & ...
            feeder.status == 1 & ...
            feeder.selectedNormal == false & ...
            feeder.normalShedable_MW > tolerance);

        if isempty(candidate)

            continue;

        end

        capacities = ...
            feeder.normalShedable_MW(candidate);

        %% -------------------------------------------------
        % First try combinations that do not overshoot
        % --------------------------------------------------

        [chosen,chosenMW] = ...
            findNormalCombination( ...
            capacities,zoneResidual);

        if isempty(chosen)

            continue;

        end

        %% -------------------------------------------------
        % Apply selected feeders
        % --------------------------------------------------

        for k = 1:length(chosen)

            feederNumber = ...
                candidate(chosen(k));

            shedMW = ...
                feeder.normalShedable_MW(feederNumber);

            feeder.PshedNormal_MW(feederNumber) = ...
                shedMW;

            feeder.Pshed_MW(feederNumber) = ...
                feeder.Pshed_MW(feederNumber) + ...
                shedMW;

            feeder.selectedNormal(feederNumber) = true;

            feeder.selected(feederNumber) = true;

            sourceBus = ...
                feeder.sourceBus(feederNumber);

            b = ...
                find(data.bus == sourceBus,1);

            feeder.busShedNormal_MW(b) = ...
                feeder.busShedNormal_MW(b) + ...
                shedMW;

            feeder.busShed_MW(b) = ...
                feeder.busShed_MW(b) + ...
                shedMW;

        end

        improvement = ...
            improvement + chosenMW;

    end

    %% -----------------------------------------------------
    % Update zone residuals
    % ------------------------------------------------------

    for z = 1:nZone

        currentZone = zoneID(z);

        buses = ...
            find(bus.zoneID == currentZone);

        feeder.zoneNormalShed_MW(z) = ...
            sum(feeder.busShedNormal_MW(buses));

        feeder.zoneResidual_MW(z) = ...
            max( ...
            feeder.zoneRequired_MW(z) - ...
            feeder.zoneNormalShed_MW(z), ...
            0);

    end

    fprintf('Cleanup round %d: residual = %.4f MW\n', ...
        round,sum(feeder.zoneResidual_MW));

    if improvement <= tolerance

        break;

    end

end

%% =========================================================
% 21. STAGE 2 FALLBACK
% CLOSEST LARGER NORMAL FEEDER
% ==========================================================

totalResidual = ...
    sum(feeder.zoneResidual_MW);

if totalResidual > allocationTolerance

    candidate = find( ...
        feeder.status == 1 & ...
        feeder.selectedNormal == false & ...
        feeder.normalShedable_MW > ...
        totalResidual + tolerance);

    if ~isempty(candidate)

        capacities = ...
            feeder.normalShedable_MW(candidate);

        difference = ...
            capacities - totalResidual;

        [~,best] = ...
            min(difference);

        feederNumber = ...
            candidate(best);

        shedMW = ...
            feeder.normalShedable_MW(feederNumber);

        feeder.PshedNormal_MW(feederNumber) = ...
            shedMW;

        feeder.Pshed_MW(feederNumber) = ...
            feeder.Pshed_MW(feederNumber) + ...
            shedMW;

        feeder.selectedNormal(feederNumber) = true;

        feeder.selected(feederNumber) = true;

        sourceBus = ...
            feeder.sourceBus(feederNumber);

        b = ...
            find(data.bus == sourceBus,1);

        feeder.busShedNormal_MW(b) = ...
            feeder.busShedNormal_MW(b) + ...
            shedMW;

        feeder.busShed_MW(b) = ...
            feeder.busShed_MW(b) + ...
            shedMW;

        fprintf('\n');
        fprintf('Larger normal feeder fallback used.\n');
        fprintf('Feeder = %s\n', ...
            feederIDText(feeder.feederID,feederNumber));
        fprintf('Shed = %.4f MW\n',shedMW);

    end

end

%% =========================================================
% 22. CALCULATE REMAINING SYSTEM REQUIREMENT
% ==========================================================

normalShed_MW = ...
    sum(feeder.PshedNormal_MW);

module8Required_MW = ...
    sum(busRequired_MW);

remaining_MW = ...
    max(module8Required_MW - normalShed_MW,0);

%% =========================================================
% 23. STAGE 3
% CRITICAL FEEDER FALLBACK
% ==========================================================

fprintf('\n');
fprintf('STAGE 3: CRITICAL FEEDER FALLBACK\n');
fprintf('---------------------------------------------\n');

feeder.criticalFallbackApplied = false;

criticalShed_MW = 0;

if remaining_MW > allocationTolerance

    %% -----------------------------------------------------
    % Find critical feeder candidates
    % ------------------------------------------------------

    candidate = find( ...
        feeder.status == 1 & ...
        feeder.selected == false & ...
        feeder.nonShedable_MW > tolerance);

    if ~isempty(candidate)

        %% -------------------------------------------------
        % Keep only feeders connected to PQ buses
        % --------------------------------------------------

        validCandidate = [];

        for k = 1:length(candidate)

            feederNumber = candidate(k);

            sourceBus = ...
                feeder.sourceBus(feederNumber);

            b = ...
                find(data.bus == sourceBus,1);

            if isempty(b)

                continue;

            end

            if isfield(data,'busType')

                if data.busType(b) == 3

                    validCandidate(end+1) = ...
                        feederNumber;

                end

            else

                validCandidate(end+1) = ...
                    feederNumber;

            end

        end

        candidate = validCandidate;

        %% -------------------------------------------------
        % Search for a critical combination
        % --------------------------------------------------

        if ~isempty(candidate)

            capacities = ...
                feeder.nonShedable_MW(candidate);

            upperLimit = ...
                remaining_MW + ...
                maxCriticalOvershoot;

            [chosen,chosenMW] = ...
                findCriticalCombination( ...
                capacities, ...
                remaining_MW, ...
                upperLimit);

            if ~isempty(chosen)

                for k = 1:length(chosen)

                    feederNumber = ...
                        candidate(chosen(k));

                    shedMW = ...
                        feeder.nonShedable_MW(feederNumber);

                    feeder.PshedCritical_MW(feederNumber) = ...
                        shedMW;

                    feeder.Pshed_MW(feederNumber) = ...
                        feeder.Pshed_MW(feederNumber) + ...
                        shedMW;

                    feeder.selectedCritical(feederNumber) = true;

                    feeder.selected(feederNumber) = true;

                    sourceBus = ...
                        feeder.sourceBus(feederNumber);

                    b = ...
                        find(data.bus == sourceBus,1);

                    feeder.busShedCritical_MW(b) = ...
                        feeder.busShedCritical_MW(b) + ...
                        shedMW;

                    feeder.busShed_MW(b) = ...
                        feeder.busShed_MW(b) + ...
                        shedMW;

                end

                criticalShed_MW = ...
                    chosenMW;

                feeder.criticalFallbackApplied = true;

            end

        end

    end

end

%% =========================================================
% 24. FINAL BUS RESULTS
% ==========================================================

for b = 1:nBus

    feeder.busResidual_MW(b) = ...
        max( ...
        busRequired_MW(b) - ...
        feeder.busShed_MW(b), ...
        0);

end

%% =========================================================
% 25. FINAL ZONE RESULTS
% ==========================================================

for z = 1:nZone

    currentZone = zoneID(z);

    buses = ...
        find(bus.zoneID == currentZone);

    feeder.zoneNormalShed_MW(z) = ...
        sum(feeder.busShedNormal_MW(buses));

    feeder.zoneCriticalShed_MW(z) = ...
        sum(feeder.busShedCritical_MW(buses));

    feeder.zoneActualShed_MW(z) = ...
        feeder.zoneNormalShed_MW(z) + ...
        feeder.zoneCriticalShed_MW(z);

    feeder.zoneResidual_MW(z) = ...
        max( ...
        feeder.zoneRequired_MW(z) - ...
        feeder.zoneActualShed_MW(z), ...
        0);

end

%% =========================================================
% 26. FINAL TOTALS
% ==========================================================

normalShed_MW = ...
    sum(feeder.PshedNormal_MW);

criticalShed_MW = ...
    sum(feeder.PshedCritical_MW);

totalShed_MW = ...
    normalShed_MW + ...
    criticalShed_MW;

finalError_MW = ...
    totalShed_MW - ...
    module8Required_MW;

finalResidual_MW = ...
    max(module8Required_MW - totalShed_MW,0);

%% =========================================================
% 27. STORE FINAL RESULTS
% ==========================================================

feeder.module8Required_MW = ...
    module8Required_MW;

feeder.totalNormalShed_MW = ...
    normalShed_MW;

feeder.totalCriticalShed_MW = ...
    criticalShed_MW;

feeder.totalPshed_MW = ...
    totalShed_MW;

feeder.totalPshed_pu = ...
    totalShed_MW / Sbase;

feeder.allocationError_MW = ...
    finalError_MW;

feeder.finalResidual_MW = ...
    finalResidual_MW;

feeder.allocationTolerance_MW = ...
    allocationTolerance;

feeder.partialFeederSheddingAllowed = false;

%% =========================================================
% 28. SELECTED FEEDERS
% ==========================================================

feeder.shedFeederIndex = ...
    find(feeder.Pshed_MW > tolerance);

feeder.shedFeederBus = ...
    feeder.sourceBus(feeder.shedFeederIndex);

feeder.shedFeederMW = ...
    feeder.Pshed_MW(feeder.shedFeederIndex);

feeder.normalFeederCount = ...
    sum(feeder.selectedNormal);

feeder.criticalFeederCount = ...
    sum(feeder.selectedCritical);

%% =========================================================
% 29. CHECK FEEDER CAPACITY
% ==========================================================

for k = 1:nFeeder

    if feeder.PshedNormal_MW(k) > ...
            feeder.normalShedable_MW(k) + tolerance

        error('Module 9: normal feeder capacity exceeded.');

    end

    if feeder.PshedCritical_MW(k) > ...
            feeder.nonShedable_MW(k) + tolerance

        error('Module 9: critical feeder capacity exceeded.');

    end

end

%% =========================================================
% 30. CHECK BINARY NORMAL FEEDER SHEDDING
% ==========================================================

for k = 1:nFeeder

    if feeder.selectedNormal(k)

        difference = ...
            abs( ...
            feeder.PshedNormal_MW(k) - ...
            feeder.normalShedable_MW(k));

        if difference > 1e-8

            error('Module 9: partial normal feeder shedding detected.');

        end

    end

end

%% =========================================================
% 31. CHECK BINARY CRITICAL FEEDER SHEDDING
% ==========================================================

for k = 1:nFeeder

    if feeder.selectedCritical(k)

        difference = ...
            abs( ...
            feeder.PshedCritical_MW(k) - ...
            feeder.nonShedable_MW(k));

        if difference > 1e-8

            error('Module 9: partial critical feeder shedding detected.');

        end

    end

end

%% =========================================================
% 32. CRITICAL OVERSHOOT CHECK
% ==========================================================

if feeder.criticalFallbackApplied

    if finalError_MW > ...
            maxCriticalOvershoot + allocationTolerance

        error('Module 9: critical overshoot is too large.');

    end

end

%% =========================================================
% 33. FINAL STATUS
% ==========================================================

if abs(finalError_MW) <= allocationTolerance

    feeder.feasible = true;

else

    feeder.feasible = false;

end

feeder.requirementSatisfied = ...
    feeder.feasible;

%% =========================================================
% 34. BUILD POST-SHEDDING OPERATING CONDITION
% ==========================================================

opPost = op;

busShed_MW = ...
    zeros(nBus,1);

%% ---------------------------------------------------------
% Add feeder shedding at each source bus
% ----------------------------------------------------------

for k = 1:nFeeder

    if feeder.Pshed_MW(k) <= tolerance

        continue;

    end

    sourceBus = ...
        feeder.sourceBus(k);

    b = ...
        find(data.bus == sourceBus,1);

    if isempty(b)

        error('Module 9: feeder source bus was not found.');

    end

    busShed_MW(b) = ...
        busShed_MW(b) + ...
        feeder.Pshed_MW(k);

end

%% ---------------------------------------------------------
% Current bus load
% ----------------------------------------------------------

currentBusLoad_MW = ...
    op.Pload(:) * Sbase;

%% ---------------------------------------------------------
% Check bus load
% ----------------------------------------------------------

for b = 1:nBus

    if busShed_MW(b) > ...
            currentBusLoad_MW(b) + 1e-8

        error('Module 9: feeder shedding exceeds bus load.');

    end

end

%% ---------------------------------------------------------
% Apply shedding to P and Q load
% ----------------------------------------------------------

for b = 1:nBus

    if currentBusLoad_MW(b) <= tolerance

        continue;

    end

    fraction = ...
        busShed_MW(b) / ...
        currentBusLoad_MW(b);

    if fraction > 1

        fraction = 1;

    end

    if fraction < 0

        fraction = 0;

    end

    opPost.Pload(b) = ...
        op.Pload(b) * ...
        (1-fraction);

    if isfield(op,'Qload')

        opPost.Qload(b) = ...
            op.Qload(b) * ...
            (1-fraction);

    end

end

%% ---------------------------------------------------------
% Store post-shedding information
% ----------------------------------------------------------

opPost.feederShedNormal_MW = ...
    feeder.PshedNormal_MW;

opPost.feederShedCritical_MW = ...
    feeder.PshedCritical_MW;

opPost.feederShed_MW = ...
    feeder.Pshed_MW;

feeder.busShedApplied_MW = ...
    busShed_MW;

feeder.opPost = ...
    opPost;

%% =========================================================
% 35. POST-SHEDDING NR CHECK
% ==========================================================

feeder.resultPost = [];

feeder.nrConverged = false;

try

    feeder.resultPost = ...
        four_newtonRaphson( ...
        data, ...
        opPost, ...
        Ybus);

    if isfield(feeder.resultPost,'converged')

        feeder.nrConverged = ...
            logical(feeder.resultPost.converged);

    else

        feeder.nrConverged = ...
            true;

    end

catch ME

    feeder.nrError = ...
        ME.message;

end

%% =========================================================
% 36. DISPLAY RESULTS
% ==========================================================

fprintf('\n');
fprintf('=============================================\n');
fprintf(' MODULE 9: FEEDER ALLOCATION\n');
fprintf('=============================================\n');

fprintf('\n');

fprintf('Required shedding  = %.4f MW\n', ...
    module8Required_MW);

fprintf('Normal shedding    = %.4f MW\n', ...
    normalShed_MW);

fprintf('Critical shedding  = %.4f MW\n', ...
    criticalShed_MW);

fprintf('Total shedding     = %.4f MW\n', ...
    totalShed_MW);

fprintf('Final residual     = %.4f MW\n', ...
    finalResidual_MW);

fprintf('Allocation error   = %.4f MW\n', ...
    finalError_MW);

fprintf('\n');

fprintf('Normal feeders selected   = %d\n', ...
    feeder.normalFeederCount);

fprintf('Critical feeders selected = %d\n', ...
    feeder.criticalFeederCount);

if feeder.criticalFallbackApplied

    fprintf('Critical fallback          = YES\n');

else

    fprintf('Critical fallback          = NO\n');

end

%% =========================================================
% 37. ZONE RESULTS
% ==========================================================

fprintf('\n');
fprintf('ZONE RESULTS\n');
fprintf('---------------------------------------------\n');

fprintf('Zone   Required   Normal   Critical   Residual\n');
fprintf('------------------------------------------------\n');

for z = 1:nZone

    fprintf('%3d   %8.3f   %8.3f   %8.3f   %8.3f\n', ...
        zoneID(z), ...
        feeder.zoneRequired_MW(z), ...
        feeder.zoneNormalShed_MW(z), ...
        feeder.zoneCriticalShed_MW(z), ...
        feeder.zoneResidual_MW(z));

end

%% =========================================================
% 38. SELECTED FEEDERS
% ==========================================================

fprintf('\n');
fprintf('SELECTED FEEDERS\n');
fprintf('---------------------------------------------\n');

for k = 1:length(feeder.shedFeederIndex)

    feederNumber = ...
        feeder.shedFeederIndex(k);

    name = ...
        feederIDText( ...
        feeder.feederID, ...
        feederNumber);

    fprintf('%s : Bus %d : %.4f MW\n', ...
        name, ...
        feeder.sourceBus(feederNumber), ...
        feeder.Pshed_MW(feederNumber));

end

%% =========================================================
% 39. FINAL STATUS
% ==========================================================

fprintf('\n');

if feeder.feasible

    fprintf('Feeder allocation status = FEASIBLE\n');

else

    fprintf('Feeder allocation status = RESIDUAL REMAINS\n');

end

if feeder.nrConverged

    fprintf('Post-shedding NR         = CONVERGED\n');

else

    fprintf('Post-shedding NR         = NOT CONVERGED / NOT RUN\n');

end

fprintf('Partial feeder shedding  = NOT ALLOWED\n');

fprintf('=============================================\n');

end


%% =========================================================
% LOCAL FUNCTION 1
% FIND NORMAL FEEDER COMBINATION
% ==========================================================

function [chosen,bestMW] = ...
    findNormalCombination(capacity,requirement)

% Find the largest combination of complete feeders
% that does NOT exceed the required amount.

chosen = [];

bestMW = 0;

capacity = capacity(:)';

n = length(capacity);

if n == 0

    return;

end

% This simple search is suitable for a small number
% of feeders.

if n > 20

    error('Too many feeders for the simple binary search.');

end

numberOfCombinations = ...
    2^n - 1;

for number = 1:numberOfCombinations

    selected = ...
        logical(bitget(number,1:n));

    totalMW = ...
        sum(capacity(selected));

    if totalMW <= requirement + 1e-9

        if totalMW > bestMW + 1e-9

            bestMW = totalMW;

            chosen = ...
                find(selected);

        end

    end

end

end


%% =========================================================
% LOCAL FUNCTION 2
% FIND CRITICAL FEEDER COMBINATION
% ==========================================================

function [chosen,bestMW] = ...
    findCriticalCombination( ...
    capacity, ...
    requirement, ...
    upperLimit)

% Find a complete feeder combination that:
%
%   requirement <= shedding <= upperLimit
%
% The combination closest to the requirement is selected.

chosen = [];

bestMW = 0;

capacity = capacity(:)';

n = length(capacity);

if n == 0

    return;

end

if n > 20

    warning('Too many critical feeders for simple binary search.');

    return;

end

bestError = inf;

numberOfCombinations = ...
    2^n - 1;

for number = 1:numberOfCombinations

    selected = ...
        logical(bitget(number,1:n));

    totalMW = ...
        sum(capacity(selected));

    % Must cover the requirement.

    if totalMW < requirement - 1e-9

        continue;

    end

    % Must not exceed the allowed overshoot.

    if totalMW > upperLimit + 1e-9

        continue;

    end

    errorMW = ...
        abs(totalMW - requirement);

    if errorMW < bestError

        bestError = errorMW;

        bestMW = totalMW;

        chosen = ...
            find(selected);

    end

end

end


%% =========================================================
% LOCAL FUNCTION 3
% FEEDER ID AS TEXT
% ==========================================================

function text = feederIDText(feederID,k)

if iscell(feederID)

    value = feederID{k};

elseif isstring(feederID)

    value = feederID(k);

elseif ischar(feederID)

    value = feederID(k,:);

else

    value = k;

end

if isstring(value)

    text = char(value);

elseif ischar(value)

    text = strtrim(value);

else

    text = sprintf('F%d',k);

end

if isempty(text)

    text = sprintf('F%d',k);

end

end
