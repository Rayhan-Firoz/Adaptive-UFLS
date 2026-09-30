function [bus, zone] = eight_BusAllocation(data, op, result, zone)

% MODULE 8
% FVSI-BASED BUS LOAD-SHEDDING ALLOCATION
%
% This module:
%   1. Calculates FVSI for PQ buses.
%   2. Finds eligible buses for load shedding.
%   3. Uses the shedding requirement from Module 7.
%   4. Allocates the required shedding to buses using FVSI.
%
% This module does NOT:
%   - perform load flow
%   - perform Newton-Raphson
%   - allocate to feeders
%   - shed protected load
%
% Feeder allocation is done in Module 9.

%% =========================================================
% 1. BASIC INFORMATION
% ==========================================================

nBus = length(data.bus);

nZone = length(zone.zoneID);

%% =========================================================
% 2. INITIALIZE BUS RESULTS
% ==========================================================

bus.FVSI = zeros(nBus,1);

bus.normalizedFVSI = zeros(nBus,1);

bus.fvsiRank = zeros(nBus,1);

bus.zoneID = zeros(nBus,1);

bus.PshedTarget_MW = zeros(nBus,1);

bus.Pshed_MW = zeros(nBus,1);

bus.Pshed_pu = zeros(nBus,1);

bus.normalShedable_MW = zeros(nBus,1);

bus.nonShedable_MW = zeros(nBus,1);

bus.critical = zeros(nBus,1);

bus.isPQ = false(nBus,1);

bus.isEligible = false(nBus,1);

%% =========================================================
% 3. FIND ZONE OF EACH BUS
% ==========================================================

for i = 1:nBus

    bus.zoneID(i) = getZoneForBus(data,i);

end

%% =========================================================
% 4. FIND PQ BUSES
% ==========================================================

PQbus = find(data.busType == 3);

for k = 1:length(PQbus)

    i = PQbus(k);

    bus.isPQ(i) = true;

end

%% =========================================================
% 5. READ CRITICAL AND NON-SHEDABLE BUS LOAD
% ==========================================================

for k = 1:length(data.regionBus)

    busNumber = data.regionBus(k);

    bus.critical(busNumber) = ...
        data.critical(k);

    bus.nonShedable_MW(busNumber) = ...
        data.nonShedable_MW(k);

end

%% =========================================================
% 6. CALCULATE SHEDABLE LOAD AT EACH BUS
% ==========================================================

for i = 1:nBus

    % Current bus load in MW.

    currentLoad_MW = ...
        op.Pload(i) * data.Sbase;

    % Protected load cannot be negative.

    protectedLoad_MW = ...
        max(bus.nonShedable_MW(i),0);

    % Protected load cannot be greater than total load.

    protectedLoad_MW = ...
        min(protectedLoad_MW,currentLoad_MW);

    bus.nonShedable_MW(i) = ...
        protectedLoad_MW;

    % Critical buses cannot be shed.

    if bus.critical(i) == 1

        bus.normalShedable_MW(i) = 0;

        bus.isEligible(i) = false;

    else

        % Normal shedable load.

        bus.normalShedable_MW(i) = ...
            currentLoad_MW - protectedLoad_MW;

        if bus.normalShedable_MW(i) < 0

            bus.normalShedable_MW(i) = 0;

        end

        % Only PQ buses with shedable load are eligible.

        if bus.isPQ(i) && ...
                bus.normalShedable_MW(i) > 0

            bus.isEligible(i) = true;

        else

            bus.isEligible(i) = false;

        end

    end

end

%% =========================================================
% 7. CHECK NR RESULTS
% ==========================================================

if ~isfield(result,'V')

    error('Module 8: result.V was not found.');

end

if ~isfield(result,'angle')

    error('Module 8: result.angle was not found.');

end

Vmag = result.V(:);

Vangle = result.angle(:);

if length(Vmag) ~= nBus

    error('Module 8: result.V does not match number of buses.');

end

if length(Vangle) ~= nBus

    error('Module 8: result.angle does not match number of buses.');

end

%% =========================================================
% 8. CREATE COMPLEX BUS VOLTAGES
% ==========================================================

Vangle_rad = Vangle * pi/180;

Vcomplex = ...
    Vmag .* exp(1i*Vangle_rad);

%% =========================================================
% 9. CALCULATE FVSI
% ==========================================================

% FVSI is calculated only for eligible PQ buses.

for k = 1:length(PQbus)

    busNumber = PQbus(k);

    if bus.isEligible(busNumber) == false

        continue;

    end

    % Find branches connected to this bus.

    connectedBranches = find( ...
        data.fromBus == busNumber | ...
        data.toBus == busNumber);

    fvsiValues = [];

    %% -----------------------------------------------------
    % Check each connected branch
    % ------------------------------------------------------

    for b = 1:length(connectedBranches)

        branch = connectedBranches(b);

        % Ignore out-of-service branches.

        if data.lineStatus(branch) == 0

            continue;

        end

        from = data.fromBus(branch);

        to = data.toBus(branch);

        R = data.Rline(branch);

        X = data.Xline(branch);

        B = data.Bline(branch);

        % FVSI cannot be calculated when X is zero.

        if abs(X) < 1e-12

            continue;

        end

        %% -------------------------------------------------
        % Transformer tap
        % --------------------------------------------------

        tapMag = data.tap(branch);

        if isnan(tapMag) || tapMag == 0

            tapMag = 1;

        end

        tapAngle = data.tapAngle(branch);

        if isnan(tapAngle)

            tapAngle = 0;

        end

        tapAngle_rad = tapAngle * pi/180;

        tap = ...
            tapMag * exp(1i*tapAngle_rad);

        %% -------------------------------------------------
        % Branch impedance
        % --------------------------------------------------

        Z = R + 1i*X;

        if abs(Z) < 1e-12

            continue;

        end

        y = 1/Z;

        ysh = 1i*B/2;

        %% -------------------------------------------------
        % Bus voltages
        % --------------------------------------------------

        Vfrom = Vcomplex(from);

        Vto = Vcomplex(to);

        %% -------------------------------------------------
        % Branch currents
        %
        % These equations are consistent with Module 3.
        % --------------------------------------------------

        I_from_to = ...
            ((y+ysh)/abs(tap)^2) * Vfrom ...
            - (y/conj(tap)) * Vto;

        I_to_from = ...
            -(y/tap) * Vfrom ...
            + (y+ysh) * Vto;

        %% -------------------------------------------------
        % Branch powers
        % --------------------------------------------------

        S_from_to = ...
            Vfrom * conj(I_from_to);

        S_to_from = ...
            Vto * conj(I_to_from);

        P_from_to = real(S_from_to);

        Q_from_to = imag(S_from_to);

        Q_to_from = imag(S_to_from);

        %% -------------------------------------------------
        % Find actual power-flow direction
        % --------------------------------------------------

        if P_from_to > 1e-10

            % Actual direction:
            % from -> to

            sendingBus = from;

            receivingBus = to;

            Vs = abs(Vfrom);

            Qr = Q_to_from;

        elseif P_from_to < -1e-10

            % Actual direction:
            % to -> from

            sendingBus = to;

            receivingBus = from;

            Vs = abs(Vto);

            Qr = Q_from_to;

        else

            % Power flow is approximately zero.

            continue;

        end

        %% -------------------------------------------------
        % Use only if this bus is receiving power
        % --------------------------------------------------

        if receivingBus ~= busNumber

            continue;

        end

        %% -------------------------------------------------
        % FVSI requires positive receiving reactive power
        % --------------------------------------------------

        if Qr <= 0

            continue;

        end

        if Vs <= 1e-12

            continue;

        end

        %% -------------------------------------------------
        % Calculate FVSI
        % --------------------------------------------------

        Zmag = sqrt(R^2 + X^2);

        FVSIvalue = ...
            4 * Zmag^2 * Qr / ...
            (Vs^2 * abs(X));

        %% -------------------------------------------------
        % Store FVSI
        % --------------------------------------------------

        if isfinite(FVSIvalue) && FVSIvalue >= 0

            fvsiValues(end+1) = FVSIvalue;

        end

    end

    %% -----------------------------------------------------
    % Keep the largest FVSI for this bus
    % ------------------------------------------------------

    if isempty(fvsiValues)

        bus.FVSI(busNumber) = 0;

    else

        bus.FVSI(busNumber) = max(fvsiValues);

    end

end

%% =========================================================
% 10. NORMALIZE FVSI WITHIN EACH ZONE
% ==========================================================

for z = 1:nZone

    currentZone = zone.zoneID(z);

    eligibleBuses = find( ...
        bus.isPQ & ...
        bus.isEligible & ...
        bus.zoneID == currentZone);

    if isempty(eligibleBuses)

        continue;

    end

    totalFVSI = ...
        sum(bus.FVSI(eligibleBuses));

    if totalFVSI > 1e-12

        for k = 1:length(eligibleBuses)

            i = eligibleBuses(k);

            bus.normalizedFVSI(i) = ...
                bus.FVSI(i) / totalFVSI;

        end

    else

        % If all FVSI values are zero,
        % give equal weight to each eligible bus.

        equalWeight = ...
            1 / length(eligibleBuses);

        for k = 1:length(eligibleBuses)

            i = eligibleBuses(k);

            bus.normalizedFVSI(i) = ...
                equalWeight;

        end

    end

end

%% =========================================================
% 11. RANK BUSES BY FVSI
% ==========================================================

for z = 1:nZone

    currentZone = zone.zoneID(z);

    eligibleBuses = find( ...
        bus.isPQ & ...
        bus.isEligible & ...
        bus.zoneID == currentZone);

    if isempty(eligibleBuses)

        continue;

    end

    [~,order] = ...
        sort(bus.FVSI(eligibleBuses),'descend');

    rankedBuses = ...
        eligibleBuses(order);

    for r = 1:length(rankedBuses)

        i = rankedBuses(r);

        bus.fvsiRank(i) = r;

    end

end

%% =========================================================
% 12. CHECK MODULE 7 RESULTS
% ==========================================================

if ~isfield(zone,'requiredPshed_MW')

    error('Module 8: zone.requiredPshed_MW was not found.');

end

if length(zone.requiredPshed_MW) ~= nZone

    error('Module 8: zone shedding data does not match zones.');

end

%% =========================================================
% 13. INITIALIZE ZONE RESULTS
% ==========================================================

zone.busAllocated_MW = zeros(nZone,1);

zone.busAllocationError_MW = zeros(nZone,1);

zone.busAllocationFeasible = false(nZone,1);

zone.remainingAfterBusAllocation_MW = ...
    zeros(nZone,1);

%% =========================================================
% 14. ALLOCATE EACH ZONE'S SHEDDING TO BUSES
% ==========================================================

for z = 1:nZone

    currentZone = zone.zoneID(z);

    target_MW = ...
        zone.requiredPshed_MW(z);

    if target_MW < 0

        target_MW = 0;

    end

    % Find eligible buses in this zone.

    eligibleBuses = find( ...
        bus.isPQ & ...
        bus.isEligible & ...
        bus.zoneID == currentZone);

    %% -----------------------------------------------------
    % No eligible bus
    % ------------------------------------------------------

    if isempty(eligibleBuses)

        zone.busAllocated_MW(z) = 0;

        zone.remainingAfterBusAllocation_MW(z) = ...
            target_MW;

        zone.busAllocationError_MW(z) = ...
            -target_MW;

        if target_MW == 0

            zone.busAllocationFeasible(z) = true;

        else

            zone.busAllocationFeasible(z) = false;

        end

        continue;

    end

    %% -----------------------------------------------------
    % Start allocation
    % ------------------------------------------------------

    remaining_MW = target_MW;

    remainingCapacity = ...
        bus.normalShedable_MW(eligibleBuses);

    %% -----------------------------------------------------
    % Continue until target is allocated
    % ------------------------------------------------------

    while remaining_MW > 1e-10

        % Find buses that still have available load.

        active = find(remainingCapacity > 1e-10);

        if isempty(active)

            break;

        end

        activeBuses = ...
            eligibleBuses(active);

        %% -------------------------------------------------
        % Get FVSI weights
        % --------------------------------------------------

        weights = ...
            bus.normalizedFVSI(activeBuses);

        totalWeight = sum(weights);

        if totalWeight <= 0

            % Equal allocation if FVSI is zero.

            weights = ...
                ones(length(activeBuses),1) / ...
                length(activeBuses);

        else

            weights = ...
                weights / totalWeight;

        end

        %% -------------------------------------------------
        % Calculate requested shedding
        % --------------------------------------------------

        requested_MW = ...
            remaining_MW * weights;

        %% -------------------------------------------------
        % Do not exceed available bus load
        % --------------------------------------------------

        available_MW = ...
            remainingCapacity(active);

        actual_MW = ...
            min(requested_MW,available_MW);

        %% -------------------------------------------------
        % Store bus shedding
        % --------------------------------------------------

        bus.Pshed_MW(activeBuses) = ...
            bus.Pshed_MW(activeBuses) + actual_MW;

        %% -------------------------------------------------
        % Update remaining target
        % --------------------------------------------------

        allocated_MW = sum(actual_MW);

        remaining_MW = ...
            remaining_MW - allocated_MW;

        %% -------------------------------------------------
        % Update remaining bus capacity
        % --------------------------------------------------

        remainingCapacity(active) = ...
            remainingCapacity(active) - actual_MW;

        %% -------------------------------------------------
        % Safety check
        % --------------------------------------------------

        if allocated_MW <= 1e-12

            break;

        end

    end

    %% -----------------------------------------------------
    % Store zone allocation result
    % ------------------------------------------------------

    busesInZone = ...
        bus.zoneID == currentZone;

    zone.busAllocated_MW(z) = ...
        sum(bus.Pshed_MW(busesInZone));

    zone.remainingAfterBusAllocation_MW(z) = ...
        max(remaining_MW,0);

    zone.busAllocationError_MW(z) = ...
        zone.busAllocated_MW(z) - target_MW;

    if abs(zone.busAllocationError_MW(z)) < 1e-8

        zone.busAllocationFeasible(z) = true;

    else

        zone.busAllocationFeasible(z) = false;

    end

end

%% =========================================================
% 15. STORE BUS TARGET
% ==========================================================

bus.PshedTarget_MW = ...
    bus.Pshed_MW;

%% =========================================================
% 16. CONVERT BUS SHEDDING TO PU
% ==========================================================

bus.Pshed_pu = ...
    bus.Pshed_MW / data.Sbase;

%% =========================================================
% 17. TOTAL BUS ALLOCATION
% ==========================================================

totalBusShed_MW = ...
    sum(bus.Pshed_MW);

totalRequired_MW = ...
    sum(zone.requiredPshed_MW);

bus.allocationError_MW = ...
    totalBusShed_MW - totalRequired_MW;

bus.totalPshed_MW = ...
    totalBusShed_MW;

bus.totalPshed_pu = ...
    totalBusShed_MW / data.Sbase;

bus.requiredPshed_MW = ...
    totalRequired_MW;

if abs(bus.allocationError_MW) < 1e-8

    bus.feasible = true;

else

    bus.feasible = false;

end

%% =========================================================
% 18. DISPLAY FVSI RESULTS
% ==========================================================

fprintf('\n');
fprintf('=============================================\n');
fprintf(' MODULE 8: FVSI BUS ALLOCATION\n');
fprintf('=============================================\n');

fprintf('\n');
fprintf('BUS FVSI INFORMATION\n');
fprintf('---------------------------------------------\n');

fprintf('Bus  Zone  Critical  FVSI      Weight    Rank   Shedable MW\n');
fprintf('-------------------------------------------------------------\n');

for i = 1:nBus

    if bus.isPQ(i)

        fprintf('%3d   %3d      %d     %8.5f   %8.5f    %3d     %10.4f\n', ...
            data.bus(i), ...
            bus.zoneID(i), ...
            bus.critical(i), ...
            bus.FVSI(i), ...
            bus.normalizedFVSI(i), ...
            bus.fvsiRank(i), ...
            bus.normalShedable_MW(i));

    end

end

%% =========================================================
% 19. DISPLAY BUS SHEDDING
% ==========================================================

fprintf('\n');
fprintf('BUS SHEDDING ALLOCATION\n');
fprintf('---------------------------------------------\n');

fprintf('Bus  Zone  Rank     Shed MW     Protected MW\n');
fprintf('------------------------------------------------\n');

for i = 1:nBus

    if bus.Pshed_MW(i) > 1e-10

        fprintf('%3d   %3d    %3d     %10.4f     %10.4f\n', ...
            data.bus(i), ...
            bus.zoneID(i), ...
            bus.fvsiRank(i), ...
            bus.Pshed_MW(i), ...
            bus.nonShedable_MW(i));

    end

end

%% =========================================================
% 20. DISPLAY ZONE CHECK
% ==========================================================

fprintf('\n');
fprintf('ZONE BUS-ALLOCATION CHECK\n');
fprintf('---------------------------------------------\n');

fprintf('Zone   Required MW   Allocated MW   Remaining MW\n');
fprintf('-------------------------------------------------\n');

for z = 1:nZone

    fprintf('%3d     %10.4f     %10.4f     %10.4f\n', ...
        zone.zoneID(z), ...
        zone.requiredPshed_MW(z), ...
        zone.busAllocated_MW(z), ...
        zone.remainingAfterBusAllocation_MW(z));

end

%% =========================================================
% 21. FINAL SUMMARY
% ==========================================================

fprintf('\n');
fprintf('---------------------------------------------\n');

fprintf('Required total shedding = %.6f MW\n', ...
    totalRequired_MW);

fprintf('Bus allocation          = %.6f MW\n', ...
    totalBusShed_MW);

fprintf('Unallocated amount      = %.6f MW\n', ...
    totalRequired_MW - totalBusShed_MW);

fprintf('Allocation error        = %.6e MW\n', ...
    bus.allocationError_MW);

if bus.feasible

    fprintf('Bus allocation status   = FEASIBLE\n');

else

    fprintf('Bus allocation status   = INSUFFICIENT BUS LOAD\n');

end

fprintf('\n');
fprintf('Protected bus load is not shed.\n');
fprintf('Feeder allocation is handled in Module 9.\n');
fprintf('Next module = Module 9\n');

fprintf('=============================================\n');

end


%% =========================================================
% LOCAL FUNCTION
% FIND ZONE OF A BUS
% ==========================================================

function currentZone = getZoneForBus(data,busNumber)

index = ...
    find(data.regionBus == busNumber,1);

if isempty(index)

    error('Bus %d was not found in Region_Data.',busNumber);

end

currentZone = ...
    data.regionID(index);

end
