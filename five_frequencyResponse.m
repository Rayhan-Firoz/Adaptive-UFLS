function freq = five_frequencyResponse(data, op, result, Ybus, verbose)

% MODULE 5
% PAPER-BASED ZONAL FREQUENCY RESPONSE
%
% This module calculates:
%
% 1. Generator frequency
% 2. Zonal COI frequency
% 3. Zonal frequency decline rate
%
% Paper Eq. (8):
%
%       f_COI = sum(H*MVA*f) / sum(H*MVA)
%
% Paper Eq. (9):
%
%       df/dt = (f_sys - f_COI) / (t_sys - t_n)
%
% No swing equation
% No ODE45
% No governor model
% No dynamic network calculation
%
% result and Ybus are kept as inputs because other modules
% already call Module 5 with these inputs.

%% =========================================================
% 1. VERBOSE OPTION
% ==========================================================

if nargin < 5

    verbose = true;

end

%% =========================================================
% 2. BASIC INFORMATION
% ==========================================================

nGen = length(data.genID);

f_sys = data.f0;

%% =========================================================
% 3. GENERATOR FREQUENCY
% ==========================================================

if ~isfield(data,'freq')

    error(['Module 5: data.freq was not found. ' ...
           'Check Module 1 generator frequency input.']);

end

fgen = data.freq(:);

if length(fgen) ~= nGen

    error(['Module 5: number of frequency values does not ' ...
           'match the number of generators.']);

end

if any(isnan(fgen))

    error('Module 5: generator frequency contains NaN values.');

end

%% =========================================================
% 4. GENERATOR INERTIA
% ==========================================================

if isfield(data,'Hgen')

    H = data.Hgen(:);

elseif isfield(data,'Hs')

    H = data.Hs(:);

elseif isfield(data,'H_s')

    H = data.H_s(:);

else

    error(['Module 5: generator inertia was not found. ' ...
           'Expected Hgen, Hs, or H_s.']);

end

if length(H) ~= nGen

    error('Module 5: inertia data does not match generators.');

end

%% =========================================================
% 5. GENERATOR MVA
% ==========================================================

if isfield(data,'machineRating')

    MVAgen = data.machineRating(:);

elseif isfield(data,'MVAgen')

    MVAgen = data.MVAgen(:);

elseif isfield(data,'MVA')

    MVAgen = data.MVA(:);

else

    error(['Module 5: generator MVA rating was not found. ' ...
           'Expected machineRating, MVAgen, or MVA.']);

end

if length(MVAgen) ~= nGen

    error('Module 5: MVA data does not match generators.');

end

%% =========================================================
% 6. GENERATOR BUS
% ==========================================================

genBus = data.genBus(:);

if length(genBus) ~= nGen

    error('Module 5: generator bus data does not match generators.');

end

%% =========================================================
% 7. TRIPPED GENERATOR
% ==========================================================

% Module 5 needs to know which generator has tripped.

if isfield(op,'tripGen')

    tripGen = round(op.tripGen);

elseif isfield(data,'tripGen')

    tripGen = round(data.tripGen);

else

    error(['Module 5: tripGen was not found. ' ...
           'Set op.tripGen before calling Module 5.']);

end

if tripGen < 1 || tripGen > nGen

    error('Module 5: invalid tripGen.');

end

tripBus = genBus(tripGen);

%% =========================================================
% 8. ACTIVE GENERATORS
% ==========================================================

% Start with all generators.
activeGen = (1:nGen)';

% Remove the tripped generator.
activeGen(tripGen) = [];

if isempty(activeGen)

    error('Module 5: no active generators remain.');

end

%% =========================================================
% 9. TIME
% ==========================================================

% Pre-disturbance time.
t_sys = 0;

% Measurement time.
if isfield(data,'t_n')

    t_n = data.t_n;

elseif isfield(data,'measurementTime')

    t_n = data.measurementTime;

else

    % Paper implementation uses 0.04 s.
    t_n = 0.04;

end

if t_n <= t_sys

    error('Module 5: measurement time must be greater than zero.');

end

%% =========================================================
% 10. ZONE INFORMATION
% ==========================================================

zoneID = unique(data.regionID);

nZone = length(zoneID);

fCOI_zone = NaN(nZone,1);

zoneInertiaWeight = zeros(nZone,1);

zoneGenerators = cell(nZone,1);

%% =========================================================
% 11. CALCULATE ZONAL COI
% ==========================================================

for z = 1:nZone

    currentZone = zoneID(z);

    % Find buses belonging to this zone.
    busesInZone = data.regionBus( ...
        data.regionID == currentZone);

    % Find generators connected to these buses.
    gensInZone = find( ...
        ismember(genBus,busesInZone));

    % Remove the tripped generator.
    gensActiveInZone = gensInZone( ...
        ismember(gensInZone,activeGen));

    zoneGenerators{z} = gensActiveInZone;

    % No active generator in this zone.
    if isempty(gensActiveInZone)

        fCOI_zone(z) = NaN;

        zoneInertiaWeight(z) = 0;

        continue;

    end

    % Get generator values.
    Hzone = H(gensActiveInZone);

    MVAzone = MVAgen(gensActiveInZone);

    Fzone = fgen(gensActiveInZone);

    % Paper Eq. (8) weight.
    weights = Hzone .* MVAzone;

    totalWeight = sum(weights);

    if totalWeight <= 0

        fCOI_zone(z) = NaN;

        zoneInertiaWeight(z) = 0;

    else

        % -------------------------------------------------
        % PAPER EQ. (8)
        % -------------------------------------------------

        fCOI_zone(z) = ...
            sum(weights .* Fzone) / totalWeight;

        zoneInertiaWeight(z) = totalWeight;

    end

end

%% =========================================================
% 12. FREQUENCY DECLINE RATE
% ==========================================================

zoneFrequencyDeclineRate = NaN(nZone,1);

for z = 1:nZone

    if isnan(fCOI_zone(z))

        zoneFrequencyDeclineRate(z) = NaN;

    else

        % -------------------------------------------------
        % PAPER EQ. (9)
        % -------------------------------------------------

        zoneFrequencyDeclineRate(z) = ...
            (f_sys - fCOI_zone(z)) / ...
            (t_sys - t_n);

    end

end

%% =========================================================
% 13. STORE RESULTS
% ==========================================================

freq.fgen = fgen;

freq.f_sys = f_sys;

freq.t_sys = t_sys;

freq.t_n = t_n;

freq.measurementInterval = t_n - t_sys;

freq.tripGen = tripGen;

freq.tripBus = tripBus;

freq.activeGen = activeGen;

freq.zoneID = zoneID;

freq.zoneGenerators = zoneGenerators;

freq.zoneInertiaWeight = zoneInertiaWeight;

freq.zoneCOI = fCOI_zone;

freq.zoneFrequencyDeclineRate = ...
    zoneFrequencyDeclineRate;

%% =========================================================
% 14. DISPLAY
% ==========================================================

if verbose

    fprintf('\n');
    fprintf('=============================================\n');
    fprintf(' MODULE 5: FREQUENCY RESPONSE\n');
    fprintf('=============================================\n');

    fprintf('Tripped generator = Gen %d\n',tripGen);

    fprintf('Tripped generator bus = Bus %d\n',tripBus);

    fprintf('System frequency = %.4f Hz\n',f_sys);

    fprintf('Measurement time = %.4f s\n',t_n);

    fprintf('\n');
    fprintf('GENERATOR FREQUENCIES\n');
    fprintf('---------------------------------------------\n');

    for g = 1:nGen

        if g == tripGen

            fprintf('Gen %2d : %.4f Hz  [TRIPPED]\n', ...
                g,fgen(g));

        else

            fprintf('Gen %2d : %.4f Hz\n', ...
                g,fgen(g));

        end

    end

    fprintf('\n');
    fprintf('ZONAL COI FREQUENCY\n');
    fprintf('---------------------------------------------\n');

    for z = 1:nZone

        if isnan(fCOI_zone(z))

            fprintf('Zone %d : No active generator\n', ...
                zoneID(z));

        else

            fprintf('Zone %d : %.4f Hz\n', ...
                zoneID(z),fCOI_zone(z));

        end

    end

    fprintf('\n');
    fprintf('ZONAL FREQUENCY DECLINE RATE\n');
    fprintf('---------------------------------------------\n');

    for z = 1:nZone

        if isnan(zoneFrequencyDeclineRate(z))

            fprintf('Zone %d : N/A\n', ...
                zoneID(z));

        else

            fprintf('Zone %d : %.4f Hz/s\n', ...
                zoneID(z), ...
                zoneFrequencyDeclineRate(z));

        end

    end

    fprintf('=============================================\n');

end

end
