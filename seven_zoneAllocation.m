function zone = seven_zoneAllocation(data, freq, ufls)

% MODULE 7
% ZONAL LOAD-SHEDDING ALLOCATION
%
% This module divides the total required load shedding
% among the different zones.
%
% The allocation is based on the frequency decline rate
% calculated in Module 5.
%
% Module 7 does NOT:
%   - run load flow
%   - run Newton-Raphson
%   - calculate FVSI
%   - allocate shedding to buses
%   - allocate shedding to feeders
%
% Bus allocation is done in Module 8.
% Feeder allocation is done in Module 9.

%% =========================================================
% 1. GET TOTAL REQUIRED SHEDDING
% ==========================================================

if ~isfield(ufls,'Pshed_MW')

    error('Module 7: Run Module 6 first.');

end

totalPshed_MW = ufls.Pshed_MW;

%% =========================================================
% 2. FIND THE ZONES
% ==========================================================

zoneID = unique(data.regionID,'stable');

nZone = length(zoneID);

%% =========================================================
% 3. GET FREQUENCY DECLINE RATE
% ==========================================================

if ~isfield(freq,'zoneFrequencyDeclineRate')

    error('Module 7: Run Module 5 first.');

end

zoneDeclineRate = ...
    freq.zoneFrequencyDeclineRate(:);

%% =========================================================
% 4. CHECK NUMBER OF ZONES
% ==========================================================

if length(zoneDeclineRate) ~= nZone

    error('Module 7: number of zones and frequency rates do not match.');

end

%% =========================================================
% 5. FIND VALID ZONES
% ==========================================================

% A zone is valid when its frequency decline rate
% is a real finite number.

validZone = isfinite(zoneDeclineRate);

%% =========================================================
% 6. GET ABSOLUTE FREQUENCY DECLINE
% ==========================================================

absoluteDeclineRate = zeros(nZone,1);

for z = 1:nZone

    if validZone(z)

        absoluteDeclineRate(z) = ...
            abs(zoneDeclineRate(z));

    else

        absoluteDeclineRate(z) = 0;

    end

end

%% =========================================================
% 7. ADD ALL VALID FREQUENCY DECLINE RATES
% ==========================================================

totalDeclineRate = ...
    sum(absoluteDeclineRate);

if totalDeclineRate <= 0

    error('Module 7: total frequency decline rate is zero.');

end

%% =========================================================
% 8. CALCULATE ZONE WEIGHTS
% ==========================================================

% Paper-based equation:
%
% Zone weight =
% frequency decline of zone
% --------------------------
% total frequency decline

zoneWeight = zeros(nZone,1);

for z = 1:nZone

    if validZone(z)

        zoneWeight(z) = ...
            absoluteDeclineRate(z) / ...
            totalDeclineRate;

    else

        zoneWeight(z) = 0;

    end

end

%% =========================================================
% 9. CHECK WEIGHTS
% ==========================================================

weightSum = sum(zoneWeight);

if abs(weightSum - 1) > 1e-10

    error('Module 7: zone weights do not add up to 1.');

end

%% =========================================================
% 10. CALCULATE REQUIRED SHEDDING FOR EACH ZONE
% ==========================================================

% Paper-based equation:
%
% Zone shedding =
% Zone weight x Total required shedding

zonePshed_MW = ...
    zoneWeight * totalPshed_MW;

%% =========================================================
% 11. CONVERT ZONE SHEDDING TO PU
% ==========================================================

zonePshed_pu = ...
    zonePshed_MW / data.Sbase;

%% =========================================================
% 12. CHECK TOTAL ZONE SHEDDING
% ==========================================================

totalZoneShed_MW = ...
    sum(zonePshed_MW);

allocationError_MW = ...
    totalZoneShed_MW - totalPshed_MW;

%% =========================================================
% 13. SAVE RESULTS
% ==========================================================

zone.zoneID = zoneID;

zone.validZone = validZone;

zone.declineRate = ...
    zoneDeclineRate;

zone.absoluteDeclineRate = ...
    absoluteDeclineRate;

zone.weight = ...
    zoneWeight;

zone.requiredPshed_MW = ...
    zonePshed_MW;

zone.requiredPshed_pu = ...
    zonePshed_pu;

zone.totalRequiredShed_MW = ...
    totalPshed_MW;

zone.totalAllocatedShed_MW = ...
    totalZoneShed_MW;

zone.allocationError_MW = ...
    allocationError_MW;

%% =========================================================
% 14. DISPLAY RESULTS
% ==========================================================

fprintf('\n');
fprintf('=============================================\n');
fprintf(' MODULE 7: ZONAL LOAD SHEDDING\n');
fprintf('=============================================\n');

fprintf('\n');

fprintf('Total required shedding = %.4f MW\n', ...
    totalPshed_MW);

fprintf('\n');

fprintf(' Zone    Decline Rate       Weight       Shedding MW\n');

fprintf('-----------------------------------------------------\n');

for z = 1:nZone

    if validZone(z)

        fprintf('%5d    %12.6f    %10.6f    %12.6f\n', ...
            zoneID(z), ...
            zoneDeclineRate(z), ...
            zoneWeight(z), ...
            zonePshed_MW(z));

    else

        fprintf('%5d        N/A          0.000000        0.000000\n', ...
            zoneID(z));

    end

end

fprintf('-----------------------------------------------------\n');

fprintf('Sum of weights      = %.6f\n', ...
    weightSum);

fprintf('Total zone shedding = %.6f MW\n', ...
    totalZoneShed_MW);

fprintf('Allocation error    = %.6e MW\n', ...
    allocationError_MW);

fprintf('\n');

if abs(allocationError_MW) < 1e-8

    fprintf('Allocation check = PASS\n');

else

    fprintf('Allocation check = FAIL\n');

end

fprintf('\n');

fprintf('Module 7 complete.\n');
fprintf('Next module = Module 8\n');

fprintf('=============================================\n');

end
