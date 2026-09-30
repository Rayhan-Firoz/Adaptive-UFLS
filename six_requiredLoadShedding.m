function ufls = six_requiredLoadShedding(data, op, result, tripGen)

% MODULE 6
% REQUIRED TOTAL LOAD SHEDDING
%
% Uses:
%   - Generator power loss
%   - Load damping
%   - Generator droop
%   - Generator headroom
%   - Target frequency
%
% No ODE
% No dynamic simulation
%
% All power calculations are done in MW.

fprintf('\n');
fprintf('=============================================\n');
fprintf(' MODULE 6: REQUIRED LOAD SHEDDING\n');
fprintf('=============================================\n');

%% =========================================================
% 1. BASIC VALUES
% ==========================================================

Sbase = data.Sbase;
f0 = data.f0;
fTarget = data.fTarget;

nGen = length(data.genBus);

%% =========================================================
% 2. TRIPPED GENERATOR
% ==========================================================

tripGen = round(tripGen);

if tripGen < 1 || tripGen > nGen

    error('Module 6: invalid tripGen.');

end

tripBus = data.genBus(tripGen);

%% =========================================================
% 3. CURRENT LOAD
% ==========================================================

% Module 2 has already applied the load factor.

load_pu = sum(op.Pload);

load_MW = load_pu * Sbase;

%% =========================================================
% 4. GENERATION LOSS
% ==========================================================

% result.Pg is the pre-trip generator output.

if length(result.Pg) < tripGen

    error('Module 6: result.Pg does not contain Gen %d.', ...
        tripGen);

end

P_loss_pu = result.Pg(tripGen);

P_loss_MW = abs(P_loss_pu) * Sbase;

%% =========================================================
% 5. LOAD DAMPING
% ==========================================================

if ~isfield(data,'loadDampingPercent')

    error('Module 6: loadDampingPercent is missing.');

end

D_percent = data.loadDampingPercent;

% Load damping in MW/Hz.

D = load_MW * ...
    (D_percent/100) / ...
    (0.01*f0);

%% =========================================================
% 6. GENERATOR DATA
% ==========================================================

if ~isfield(data,'governor')

    error('Module 6: data.governor is missing.');

end

if ~isfield(data,'machineRating')

    error('Module 6: data.machineRating is missing.');

end

if ~isfield(data,'Pmax_MW')

    error('Module 6: data.Pmax_MW is missing.');

end

R = data.governor(:);

MVA = data.machineRating(:);

Pmax = data.Pmax_MW(:);

% Generator output before the trip.

Pg_MW = result.Pg(:) * Sbase;

%% =========================================================
% 7. CHECK GENERATOR DATA
% ==========================================================

if length(R) ~= nGen

    error('Module 6: governor data does not match generators.');

end

if length(MVA) ~= nGen

    error('Module 6: machine rating does not match generators.');

end

if length(Pmax) ~= nGen

    error('Module 6: Pmax data does not match generators.');

end

if length(Pg_MW) ~= nGen

    error('Module 6: result.Pg does not match generators.');

end

%% =========================================================
% 8. GOVERNOR RESPONSE AND HEADROOM
% ==========================================================

Kgov = zeros(nGen,1);

headroom = zeros(nGen,1);

for g = 1:nGen

    % The tripped generator cannot respond.

    if g == tripGen

        Kgov(g) = 0;

        headroom(g) = 0;

    else

        if R(g) <= 0

            error('Module 6: invalid droop for Gen %d.',g);

        end

        % Governor response in MW/Hz.

        Kgov(g) = ...
            MVA(g) / (R(g)*f0);

        % Available generation headroom.

        headroom(g) = ...
            Pmax(g) - Pg_MW(g);

        if headroom(g) < 0

            headroom(g) = 0;

        end

    end

end

%% =========================================================
% 9. FREQUENCY WITHOUT LOAD SHEDDING
% ==========================================================

% We solve:
%
% Generation loss =
% Load damping response + governor response
%
% using simple bisection.

low = 0;

high = 1;

% First find an upper limit.

for k = 1:100

    governorPower = 0;

    for g = 1:nGen

        response = Kgov(g) * high;

        if response > headroom(g)

            response = headroom(g);

        end

        governorPower = ...
            governorPower + response;

    end

    totalResponse = ...
        D*high + governorPower;

    if totalResponse >= P_loss_MW

        break;

    end

    high = high * 2;

end

if totalResponse < P_loss_MW

    error('Module 6: could not find frequency-response solution.');

end

% Bisection.

for k = 1:100

    middle = ...
        (low + high)/2;

    governorPower = 0;

    for g = 1:nGen

        response = ...
            Kgov(g) * middle;

        if response > headroom(g)

            response = headroom(g);

        end

        governorPower = ...
            governorPower + response;

    end

    totalResponse = ...
        D*middle + governorPower;

    if totalResponse < P_loss_MW

        low = middle;

    else

        high = middle;

    end

end

deltaF = ...
    (low + high)/2;

frequencyWithoutShedding = ...
    f0 - deltaF;

%% =========================================================
% 10. TARGET FREQUENCY
% ==========================================================

targetDeltaF = ...
    f0 - fTarget;

if targetDeltaF < 0

    targetDeltaF = 0;

end

%% =========================================================
% 11. GOVERNOR RESPONSE AT TARGET FREQUENCY
% ==========================================================

governorAtTarget = zeros(nGen,1);

for g = 1:nGen

    response = ...
        Kgov(g) * targetDeltaF;

    if response > headroom(g)

        response = headroom(g);

    end

    governorAtTarget(g) = response;

end

totalGovernorAtTarget = ...
    sum(governorAtTarget);

%% =========================================================
% 12. REQUIRED LOAD SHEDDING
% ==========================================================

shed_MW = 0;

for k = 1:50

    % Load remaining after shedding.

    remainingLoad = ...
        load_MW - shed_MW;

    if remainingLoad < 0

        remainingLoad = 0;

    end

    % New load damping.

    D_after = ...
        remainingLoad * ...
        (D_percent/100) / ...
        (0.01*f0);

    % Natural response at target frequency.

    naturalResponse = ...
        D_after*targetDeltaF + ...
        totalGovernorAtTarget;

    % Required shedding.

    newShed = ...
        P_loss_MW - naturalResponse;

    if newShed < 0

        newShed = 0;

    end

    if newShed > load_MW

        newShed = load_MW;

    end

    % Check convergence.

    if abs(newShed - shed_MW) < 1e-6

        shed_MW = newShed;

        break;

    end

    shed_MW = newShed;

end

%% =========================================================
% 13. FINAL VALUES
% ==========================================================

remainingLoad = ...
    load_MW - shed_MW;

if remainingLoad < 0

    remainingLoad = 0;

end

D_after = ...
    remainingLoad * ...
    (D_percent/100) / ...
    (0.01*f0);

naturalResponse = ...
    D_after*targetDeltaF + ...
    totalGovernorAtTarget;

%% =========================================================
% 14. FREQUENCY SECURITY
% ==========================================================

if frequencyWithoutShedding >= fTarget

    frequencySafe = 1;

else

    frequencySafe = 0;

end

%% =========================================================
% 15. STORE RESULTS
% ==========================================================

ufls.tripGen = tripGen;

ufls.tripBus = tripBus;

ufls.totalLoad_MW = load_MW;

ufls.totalLoad_pu = load_pu;

ufls.Ploss_MW = P_loss_MW;

ufls.Ploss_pu = P_loss_pu;

ufls.f_sys = f0;

ufls.f_TH = fTarget;

ufls.delta_f_Hz = deltaF;

ufls.frequencyWithoutShedding_Hz = ...
    frequencyWithoutShedding;

ufls.frequencySecuritySatisfied = ...
    frequencySafe;

ufls.loadDampingPercent = ...
    D_percent;

ufls.D_MW_per_Hz = ...
    D;

ufls.D_after_MW_per_Hz = ...
    D_after;

ufls.governor_MW_per_Hz = ...
    Kgov;

ufls.headroom_MW = ...
    headroom;

ufls.governorResponseAtTarget_MW = ...
    governorAtTarget;

ufls.totalGovernorAtTarget_MW = ...
    totalGovernorAtTarget;

ufls.targetDeltaF_Hz = ...
    targetDeltaF;

ufls.naturalResponseAtTarget_MW = ...
    naturalResponse;

ufls.requiredShed_MW = ...
    shed_MW;

ufls.Pshed_MW = ...
    shed_MW;

ufls.Pshed_pu = ...
    shed_MW / Sbase;

ufls.required = ...
    shed_MW > 0;

%% =========================================================
% 16. DISPLAY
% ==========================================================

fprintf('\n');

fprintf('Tripped generator       = Gen %d\n', ...
    tripGen);

fprintf('Tripped generator bus   = Bus %d\n', ...
    tripBus);

fprintf('Current load            = %.4f MW\n', ...
    load_MW);

fprintf('Generation loss         = %.4f MW\n', ...
    P_loss_MW);

fprintf('Load damping            = %.4f %%\n', ...
    D_percent);

fprintf('Load damping D          = %.6f MW/Hz\n', ...
    D);

fprintf('\n');

fprintf('Frequency without UFLS  = %.4f Hz\n', ...
    frequencyWithoutShedding);

fprintf('Target frequency        = %.4f Hz\n', ...
    fTarget);

fprintf('Target frequency drop   = %.4f Hz\n', ...
    targetDeltaF);

fprintf('\n');

fprintf('Governor response       = %.4f MW\n', ...
    totalGovernorAtTarget);

fprintf('Natural response        = %.4f MW\n', ...
    naturalResponse);

fprintf('Required shedding       = %.4f MW\n', ...
    shed_MW);

if frequencySafe == 1

    fprintf('Frequency condition     = SATISFIED\n');

else

    fprintf('Frequency condition     = NOT SATISFIED\n');

end

fprintf('=============================================\n');

end
