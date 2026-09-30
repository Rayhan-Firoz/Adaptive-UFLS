function result11 = eleven_frequencyExcursion(data, op, result, post)
%==========================================================================
% MODULE 11
% POST-UFLS FREQUENCY EXCURSION
%
% Sequence:
%   1. Start from the pre-contingency NR operating point.
%   2. Calculate initial transient internal EMF E' of all generators.
%   3. Trip the specified generator.
%   4. Simulate frequency decline with PRE-UFLS network/load.
%   5. Detect the UFLS trigger frequency.
%   6. Continue for the specified UFLS delay.
%   7. Apply the ACTUAL load shedding calculated by Module 10.
%   8. Switch to the POST-UFLS network/load.
%   9. Continue the dynamic simulation.
%
% Main script call:
%
%   result11 = eleven_frequencyExcursion(data, op, result, post);
%
% IMPORTANT:
%   result       = Module 4 PRE-UFLS NR result
%   post.result  = Module 10 POST-UFLS NR result
%   post.op      = Module 10 POST-UFLS operating condition
%   post.Pg_pre  = pre-trip generator active power
%   post.Qg_pre  = pre-trip generator reactive power
%
% GOVERNOR MODEL:
%   Generator-specific droop is taken from:
%
%       data.governor(g)
%
%   Governor response:
%
%       Kgov_g = MVA_g / (R_g * f0)
%
%   where R_g is the generator droop in pu.
%
% LOAD-FREQUENCY RESPONSE:
%   The reference defines LFR as percentage load change for every
%   1% frequency change.
%
%   Therefore:
%
%       Dload = kp * Pload / f0
%
%   where:
%       kp    = LFR as a fraction
%       Pload = load in MW
%       f0    = nominal frequency in Hz
%
%   Dload has units MW/Hz.
%
% DYNAMIC GOVERNOR MODEL:
%   A first-order governor and first-order turbine are used.
%   The droop gain is taken from data.governor(g).
%   Because the workbook does not contain governor/turbine time constants,
%   explicit project assumptions are used below and are stored in result11.
%
%   Tgov = 0.20 s
%   Tturb = 0.50 s
%
%   The governor command is limited by generator headroom based on
%   data.Pmax. No fourth-order machine model is introduced.
%
% LOAD-DAMPING DISTRIBUTION:
%   The aggregate load-frequency response is distributed among the
%   active generator swing equations according to inertia so that the
%   resulting COI response represents the aggregate system response.
%
%==========================================================================


%% ========================================================================
% 1. BASIC CHECKS
% =========================================================================

requiredData = { ...
    'bus', ...
    'genBus', ...
    'Hgen', ...
    'machineRating', ...
    'Xd1', ...
    'Dgen', ...
    'governor', ...
    'Sbase', ...
    'f0'};

for k = 1:length(requiredData)

    if ~isfield(data,requiredData{k})

        error('Module 11: data.%s is missing.', ...
            requiredData{k});

    end

end


if ~isfield(data,'UFLStrigger')

    error('Module 11: data.UFLStrigger is missing.');

end


if ~isfield(data,'UFLSdelay')

    error('Module 11: data.UFLSdelay is missing.');

end


if ~isfield(op,'tripGen') && ~isfield(post,'tripGen')

    error('Module 11: tripGen is not available.');

end


if ~isfield(post,'op')

    error('Module 11: post.op is missing.');

end


if ~isfield(post,'result')

    error('Module 11: post.result is missing.');

end


if ~isfield(post,'Pg_pre')

    error('Module 11: post.Pg_pre is missing.');

end


if ~isfield(post,'Qg_pre')

    error('Module 11: post.Qg_pre is missing.');

end


%% ========================================================================
% 2. SYSTEM PARAMETERS
% =========================================================================

Sbase = data.Sbase(1);
f0    = data.f0(1);

omega_s = 2*pi*f0;


if Sbase <= 0

    error('Module 11: Sbase must be positive.');

end


if f0 <= 0

    error('Module 11: nominal frequency f0 must be positive.');

end


busNumbers = data.bus(:);

genBus = data.genBus(:);

nBus = length(busNumbers);
nGen = length(genBus);


% Check that bus numbers are unique.

if length(unique(busNumbers)) ~= nBus

    error('Module 11: duplicate bus numbers detected.');

end


% Check that generator bus numbers exist.

for g = 1:nGen

    if ~ismember(genBus(g),busNumbers)

        error(['Module 11: Generator %d is assigned to Bus %d, ', ...
               'but that bus does not exist in data.bus.'], ...
            g,genBus(g));

    end

end


%% ========================================================================
% 3. GENERATOR TRIP
% =========================================================================

if isfield(op,'tripGen') && ~isempty(op.tripGen)

    tripGen = op.tripGen;

elseif isfield(post,'tripGen') && ~isempty(post.tripGen)

    tripGen = post.tripGen;

else

    error('Module 11: tripGen is not available.');

end


if ~isscalar(tripGen) || ...
   tripGen < 1 || ...
   tripGen > nGen || ...
   tripGen ~= round(tripGen)

    error('Module 11: invalid tripGen = %g.',tripGen);

end


tripGen = round(tripGen);


%% ========================================================================
% 4. PRE- AND POST-UFLS OPERATING CONDITIONS
% =========================================================================

opPre  = op;
opPost = post.op;


opPre.tripGen  = tripGen;
opPost.tripGen = tripGen;


%% ========================================================================
% 5. GENERATOR INFORMATION
% =========================================================================

Hgen = data.Hgen(:);

machineRating = data.machineRating(:);

Xd1 = data.Xd1(:);

Dgen = data.Dgen(:);

Rgen = data.governor(:);


% Check dimensions.

if length(Hgen) ~= nGen
    error('Module 11: Hgen length does not match number of generators.');
end

if length(machineRating) ~= nGen
    error('Module 11: machineRating length does not match number of generators.');
end

if length(Xd1) ~= nGen
    error('Module 11: Xd1 length does not match number of generators.');
end

if length(Dgen) ~= nGen
    error('Module 11: Dgen length does not match number of generators.');
end

if length(Rgen) ~= nGen
    error('Module 11: governor length does not match number of generators.');
end



% Validate generator parameters.

if any(~isfinite(Hgen)) || any(Hgen <= 0)

    error('Module 11: all generator inertia constants Hgen must be positive.');

end


if any(~isfinite(machineRating)) || any(machineRating <= 0)

    error('Module 11: all machine ratings must be positive.');

end


if any(~isfinite(Xd1)) || any(Xd1 <= 0)

    error('Module 11: all Xd1 values must be positive.');

end


if any(~isfinite(Rgen)) || any(Rgen <= 0)

    error('Module 11: all governor droop values R must be positive.');

end


if any(~isfinite(Dgen))

    error('Module 11: generator damping values contain invalid entries.');

end


%% ========================================================================
% 6. PRE-TRIP MECHANICAL POWERS
% =========================================================================

PgPre = post.Pg_pre(:);

QgPre = post.Qg_pre(:);


if length(PgPre) < nGen

    error('Module 11: post.Pg_pre has fewer entries than generators.');

end


if length(QgPre) < nGen

    error('Module 11: post.Qg_pre has fewer entries than generators.');

end


PgPre = PgPre(1:nGen);

QgPre = QgPre(1:nGen);


if any(~isfinite(PgPre))

    error('Module 11: Pg_pre contains invalid values.');

end


if any(~isfinite(QgPre))

    error('Module 11: Qg_pre contains invalid values.');

end


%% ========================================================================
% 7. ACTIVE GENERATORS AFTER CONTINGENCY
% =========================================================================

activeGen = setdiff((1:nGen).',tripGen);

nActive = length(activeGen);


if isempty(activeGen)

    error('Module 11: no active generators remain after trip.');

end


Hactive       = Hgen(activeGen);
MVAactive     = machineRating(activeGen);
DgenActive    = Dgen(activeGen);
Ractive       = Rgen(activeGen);
Xd1Active     = Xd1(activeGen);

Pm0           = PgPre(activeGen);
Qg0           = QgPre(activeGen);


% System-base inertia constants.

HsysActive = ...
    Hactive .* MVAactive ./ Sbase;


if any(HsysActive <= 0)

    error('Module 11: active-generator system-base inertia is invalid.');

end


%% ========================================================================
% 8. INITIAL PRE-CONTINGENCY VOLTAGE
%
% IMPORTANT:
% Initial generator voltage comes from Module 4 PRE-UFLS NR.
%
% Do NOT initialize E' using post.result.V.
% =========================================================================

if ~isfield(result,'V')

    error('Module 11: Module 4 result.V is missing.');

end


if ~isfield(result,'angle')

    error('Module 11: Module 4 result.angle is missing.');

end


Vpre = result.V(:);

anglePre = result.angle(:);


if length(Vpre) ~= nBus

    error(['Module 11: Module 4 voltage vector has %d entries, ', ...
           'but system contains %d buses.'], ...
        length(Vpre),nBus);

end


if length(anglePre) ~= nBus

    error(['Module 11: Module 4 angle vector has %d entries, ', ...
           'but system contains %d buses.'], ...
        length(anglePre),nBus);

end


if any(~isfinite(Vpre)) || any(Vpre <= 0)

    error('Module 11: invalid pre-contingency bus voltage magnitude.');

end


if any(~isfinite(anglePre))

    error('Module 11: invalid pre-contingency bus angles.');

end


% Detect whether angles are degrees or radians.

if max(abs(anglePre)) > 2*pi

    anglePreRad = deg2rad(anglePre);

else

    anglePreRad = anglePre;

end


VcomplexPre = ...
    Vpre .* exp(1j*anglePreRad);


%% ========================================================================
% 9. GENERATOR TERMINAL VOLTAGES
% =========================================================================

VgenPre = zeros(nGen,1);


for g = 1:nGen

    busIndex = ...
        find(busNumbers == genBus(g),1);

    if isempty(busIndex)

        error(['Module 11: Generator %d bus %d ', ...
               'could not be mapped to a bus index.'], ...
            g,genBus(g));

    end


    VgenPre(g) = VcomplexPre(busIndex);

end


%% ========================================================================
% 10. INITIAL TRANSIENT INTERNAL EMF E'
%
% E' = V + j Xd' I
%
% I = conj(S/V)
%
% Xd' is converted from generator base to system base:
%
% Xd'_system = Xd'_generator * Sbase / MVA_generator
%
% =========================================================================

EprimeAll = zeros(nGen,1);


for g = 1:nGen

    if abs(VgenPre(g)) < 1e-8

        error(['Module 11: Generator %d has near-zero ', ...
               'terminal voltage.'],g);

    end


    Sgen = ...
        PgPre(g) + 1j*QgPre(g);


    Igen = ...
        conj(Sgen / VgenPre(g));


    Xd1System = ...
        Xd1(g) * Sbase / machineRating(g);


    EprimeAll(g) = ...
        VgenPre(g) + ...
        1j*Xd1System*Igen;

end


Eactive = EprimeAll(activeGen);


%% ========================================================================
% 11. PRINT HEADER
% =========================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' MODULE 11 - POST-UFLS FREQUENCY EXCURSION\n');
fprintf('============================================================\n');


fprintf('\nGenerator contingency:\n');

fprintf('  Tripped generator : Gen %d\n',tripGen);

fprintf('  Tripped bus       : Bus %d\n',genBus(tripGen));


%% ========================================================================
% 12. ACTIVE GENERATOR INFORMATION
% =========================================================================

fprintf('\nActive generators after trip:\n');


for k = 1:nActive

    g = activeGen(k);


    fprintf(['  Gen %2d -> Bus %4d   ', ...
             'Pm = %10.4f MW   ', ...
             'H = %.4f s   ', ...
             'R = %.6f pu\n'], ...
        g, ...
        genBus(g), ...
        Pm0(k)*Sbase, ...
        Hactive(k), ...
        Ractive(k));

end


%% ========================================================================
% 13. INITIAL E'
% =========================================================================

fprintf('\nInitial transient internal EMF E'':\n');


for g = 1:nGen

    fprintf(['  Gen %2d: |E''| = %.6f pu, ', ...
             'angle = %.6f deg\n'], ...
        g, ...
        abs(EprimeAll(g)), ...
        rad2deg(angle(EprimeAll(g))));

end


%% ========================================================================
% 14. LOAD INFORMATION
% =========================================================================

if ~isfield(opPre,'Pload')

    error('Module 11: opPre.Pload is missing.');

end


if ~isfield(opPost,'Pload')

    error('Module 11: post.op.Pload is missing.');

end


prePload = opPre.Pload(:);

postPload = opPost.Pload(:);


if length(prePload) ~= nBus

    error('Module 11: pre-UFLS Pload does not match bus count.');

end


if length(postPload) ~= nBus

    error('Module 11: post-UFLS Pload does not match bus count.');

end


preLoadMW = ...
    sum(prePload) * Sbase;


postLoadMW = ...
    sum(postPload) * Sbase;


actualLoadReduction = ...
    preLoadMW - postLoadMW;


fprintf('\nLoad conditions:\n');

fprintf('  Pre-UFLS load        = %.4f MW\n', ...
    preLoadMW);

fprintf('  Post-UFLS load       = %.4f MW\n', ...
    postLoadMW);

fprintf('  Actual load shedding = %.4f MW\n', ...
    actualLoadReduction);

%% ========================================================================
% 15. UFLS SETTINGS
% =========================================================================

fTrigger = data.UFLStrigger(1);

UFLSdelay = data.UFLSdelay(1);


if ~isfinite(fTrigger) || fTrigger <= 0

    error('Module 11: invalid UFLS trigger frequency.');

end


if ~isfinite(UFLSdelay) || UFLSdelay < 0

    error('Module 11: UFLS delay must be non-negative.');

end


fprintf('\nUFLS settings:\n');

fprintf('  Trigger frequency = %.4f Hz\n',fTrigger);

fprintf('  UFLS delay        = %.4f s\n',UFLSdelay);


%% ========================================================================
% 16. BUILD PRE-UFLS LOAD ADMITTANCE
%
% Constant impedance representation around the NR operating point:
%
% Yload = conj(Sload)/|V|^2
%
% Solar active power is represented as negative load.
% =========================================================================

YloadPre = ...
    buildLoadAdmittance( ...
        data, ...
        opPre, ...
        Vpre);


%% ========================================================================
% 17. BUILD POST-UFLS LOAD ADMITTANCE
%
% Use the actual post-UFLS NR voltage from Module 10.
%
% This voltage is used only to parameterize the remaining load.
% It does NOT initialize generator E'.
% =========================================================================

if ~isfield(post.result,'V')

    error('Module 11: post.result.V is missing.');

end


Vpost = post.result.V(:);


if length(Vpost) ~= nBus

    error('Module 11: post-UFLS voltage vector does not match bus count.');

end


if any(~isfinite(Vpost)) || any(Vpost <= 0)

    error('Module 11: invalid post-UFLS bus voltage magnitude.');

end


YloadPost = ...
    buildLoadAdmittance( ...
        data, ...
        opPost, ...
        Vpost);


%% ========================================================================
% 18. GET PRE- AND POST-UFLS YBUS
% =========================================================================
%
% PRE-UFLS:
% Use the original network topology before feeder shedding.
%
% POST-UFLS:
% Use the Ybus produced by Module 10 after actual feeder shedding.
% =========================================================================

%----------------------------------------------------------------------
% PRE-UFLS Ybus
%----------------------------------------------------------------------
YbusPre = three_Ybus(data);

if size(YbusPre,1) ~= nBus || size(YbusPre,2) ~= nBus
    error('Module 11: PRE-UFLS Ybus dimensions do not match bus count.');
end

fprintf('\nNetwork topology:\n');
fprintf(' Using PRE-UFLS Ybus for generator-trip stages.\n');

%----------------------------------------------------------------------
% POST-UFLS Ybus
%----------------------------------------------------------------------
if ~isfield(post,'Ybus') || isempty(post.Ybus)
    error(['Module 11: post.Ybus is missing. ', ...
           'Module 10 POST-UFLS Ybus is required.']);
end

YbusPost = post.Ybus;

if size(YbusPost,1) ~= nBus || size(YbusPost,2) ~= nBus
    error('Module 11: POST-UFLS Ybus dimensions do not match bus count.');
end

fprintf(' Using POST-UFLS Ybus for post-shedding stage.\n');


%% ========================================================================
% 19. CONVERT ALL Xd' VALUES TO SYSTEM BASE
% =========================================================================

Xd1SystemAll = zeros(nGen,1);


for g = 1:nGen

    Xd1SystemAll(g) = ...
        Xd1(g) * Sbase / machineRating(g);

end


%% ========================================================================
% 20. BUILD PRE-CONTINGENCY REDUCED NETWORK
% =========================================================================

allGen = (1:nGen).';


YredPreFull = ...
    buildReducedNetwork( ...
        YbusPre, ...
        YloadPre, ...
        genBus, ...
        allGen, ...
        Xd1SystemAll, ...
        data);


%% ========================================================================
% 21. PRE-TRIP EQUILIBRIUM CHECK
%
% The initial E' and reduced network should reproduce the
% pre-contingency generator active powers.
% =========================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' PRE-TRIP EQUILIBRIUM CHECK\n');
fprintf('============================================================\n');


PePreFull = ...
    real(EprimeAll .* ...
    conj(YredPreFull * EprimeAll));


equilibriumError = ...
    PgPre - PePreFull;


for g = 1:nGen

    fprintf(['  Gen %2d: Pm = %10.4f MW, ', ...
             'Pe = %10.4f MW, ', ...
             'error = %10.4f MW\n'], ...
        g, ...
        PgPre(g)*Sbase, ...
        PePreFull(g)*Sbase, ...
        equilibriumError(g)*Sbase);

end


maxEquilibriumError = ...
    max(abs(equilibriumError))*Sbase;


fprintf('\n');

fprintf('Maximum generator power mismatch = %.6f MW\n', ...
    maxEquilibriumError);


equilibriumToleranceMW = 1e-3;

if maxEquilibriumError > equilibriumToleranceMW
    error(['Module 11: pre-trip dynamic equilibrium failed. ', ...
           'Maximum mismatch = %.6f MW.'], ...
           maxEquilibriumError);
end

fprintf('Equilibrium check: GOOD\n');


%% ========================================================================
% 22. BUILD POST-TRIP PRE-UFLS NETWORK
% =========================================================================

YredPre = ...
    buildReducedNetwork( ...
        YbusPre, ...
        YloadPre, ...
        genBus, ...
        activeGen, ...
        Xd1SystemAll,...
        data);


%% ========================================================================
% 23. INITIAL POST-TRIP POWER BALANCE
% =========================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' INITIAL POST-TRIP POWER BALANCE\n');
fprintf('============================================================\n');


PeInitialTrip = ...
    real(Eactive .* ...
    conj(YredPre * Eactive));


initialMismatch = ...
    Pm0 - PeInitialTrip;


for k = 1:nActive

    g = activeGen(k);


    fprintf(['  Gen %2d: Pm = %10.4f MW, ', ...
             'Pe = %10.4f MW, ', ...
             'Pm-Pe = %10.4f MW\n'], ...
        g, ...
        Pm0(k)*Sbase, ...
        PeInitialTrip(k)*Sbase, ...
        initialMismatch(k)*Sbase);

end


totalInitialMismatchMW = ...
    sum(initialMismatch)*Sbase;


fprintf('\n');

fprintf('Total initial post-trip mismatch = %.6f MW\n', ...
    totalInitialMismatchMW);


%% ========================================================================
% 24. BUILD POST-UFLS REDUCED NETWORK
% =========================================================================

YredPost = ...
    buildReducedNetwork( ...
        YbusPost, ...
        YloadPost, ...
        genBus, ...
        activeGen, ...
        Xd1SystemAll, ...
        data);


%% ========================================================================
% 25. LOAD-FREQUENCY RESPONSE / LOAD DAMPING
% =========================================================================
%
% Load_Damping_Percent is stored as a percentage number:
%
%   1.5  = 1.5%
%   2.0  = 2.0%
%
% Reference definition:
% LFR = percentage load change for every 1% frequency change.
%
% Therefore:
%
% Dload(MW/Hz) =
%     Pload(MW) * (D_percent/100) / (0.01*f0)
%
% which is equivalent to:
%
% Dload(MW/Hz) =
%     Pload(MW) * D_percent / f0
%
% when D_percent is entered as 1.5 for 1.5%.
% =========================================================================

if ~isfield(data,'loadDampingPercent')
    error('Module 11: data.loadDampingPercent is missing.');
end

D_percent = data.loadDampingPercent(1);

if ~isfinite(D_percent) || D_percent < 0
    error('Module 11: invalid Load_Damping_Percent value.');
end

% Convert percentage LFR to MW/Hz.
DloadPreMWHz = ...
    preLoadMW * (D_percent/100) / (0.01*f0);

DloadPostMWHz = ...
    postLoadMW * (D_percent/100) / (0.01*f0);

fprintf('\nLoad-frequency response:\n');
fprintf(' LFR = %.6f %%\n',D_percent);
fprintf(' Pre-UFLS D = %.6f MW/Hz\n', ...
    DloadPreMWHz);
fprintf(' Post-UFLS D = %.6f MW/Hz\n', ...
    DloadPostMWHz);


%% ========================================================================
% 26. GOVERNOR DROOP AND DYNAMIC GOVERNOR/TURBINE PARAMETERS
% =========================================================================
%
% Static droop gain is retained from the existing Module 6 formulation:
%
%   Kgov(MW/Hz) = MVA / (R*f0)
%
% The dynamic model adds first-order governor and turbine lags:
%
%   dPgov/dt  = (Pgov_cmd - Pgov) / Tgov
%   dPturb/dt = (Pgov - Pturb) / Tturb
%
% where Pgov and Pturb are incremental mechanical-power states in pu.
%
% The workbook does not contain Tgov or Tturb, so the following are
% explicit model assumptions rather than measured workbook data.
% =========================================================================

Ractive = ...
    Rgen(activeGen);

GovGainMWHz = ...
    MVAactive ./ ...
    (Ractive .* f0);

GovGainPuHz = ...
    GovGainMWHz ./ Sbase;

%--------------------------------------------------------------------------
% Explicit dynamic-governor assumptions.
%--------------------------------------------------------------------------
Tgov = 0.20;       % governor time constant, s
Tturb = 0.50;      % turbine time constant, s

if Tgov <= 0 || Tturb <= 0
    error('Module 11: Tgov and Tturb must be positive.');
end

%--------------------------------------------------------------------------
% Generator headroom from Pmax.
% data.Pmax is on system base in one_readInputData.m.
%--------------------------------------------------------------------------
if ~isfield(data,'Pmax')
    error('Module 11: data.Pmax is required for governor headroom.');
end

PmaxAllPu = data.Pmax(:);

if length(PmaxAllPu) ~= nGen
    error('Module 11: data.Pmax length does not match generator count.');
end

GovHeadroomPu = ...
    max(PmaxAllPu(activeGen) - Pm0,0);

GovHeadroomMW = ...
    GovHeadroomPu * Sbase;

fprintf('\nGovernor response used in dynamic model:\n');

for k = 1:nActive

    g = activeGen(k);

    fprintf(['  Gen %2d: R = %.6f pu, ', ...
             'Rating = %.4f MVA, ', ...
             'Kgov = %.6f MW/Hz, ', ...
             'Headroom = %.4f MW\n'], ...
        g, ...
        Ractive(k), ...
        MVAactive(k), ...
        GovGainMWHz(k), ...
        GovHeadroomMW(k));

end

fprintf('  Total governor droop gain = %.6f MW/Hz\n', ...
    sum(GovGainMWHz));

fprintf('  Governor time constant     = %.3f s (assumed)\n',Tgov);
fprintf('  Turbine time constant      = %.3f s (assumed)\n',Tturb);
fprintf('  Total governor headroom    = %.6f MW\n', ...
    sum(GovHeadroomMW));


%% ========================================================================
% 27. INITIAL STATE
% =========================================================================
%
% x = [delta, omega, PgovIncrement, PturbIncrement]'
%
% delta               = generator internal-E' angle, rad
% omega               = generator speed, pu
% PgovIncrement       = incremental governor output, pu
% PturbIncrement      = incremental turbine mechanical power, pu
%
% All dynamic states start at the pre-disturbance equilibrium:
%
%   PgovIncrement  = 0
%   PturbIncrement = 0
%
% Therefore the initial mechanical power is exactly PgPre.
% =========================================================================

delta0 = ...
    angle(Eactive);

omega0 = ...
    ones(nActive,1);

Pgov0 = ...
    zeros(nActive,1);

Pturb0 = ...
    zeros(nActive,1);

x0 = ...
    [delta0;omega0;Pgov0;Pturb0];

%% ========================================================================
% 28. SIMULATION TIME
% =========================================================================

simulationTime = 300;


%% ========================================================================
% 29. INITIAL ROCOF ESTIMATE
%
% This is the initial COI acceleration immediately after the generator
% trip, before significant frequency-dependent response develops.
% =========================================================================

initialROCOFEstimate = ...
    f0 * ...
    sum(initialMismatch) / ...
    (2*sum(HsysActive));


%% ========================================================================
% 29A. AGGREGATE PHYSICAL DISTURBANCE
%
% The tripped generator represents a real loss of generation.
%
% Before UFLS:
%       disturbance = - generation loss
%
% After UFLS:
%       disturbance = - generation loss + actual load shedding
% =========================================================================

tripLossMW = ...
    PgPre(tripGen) * Sbase;

preUFLSDisturbancePu = ...
    -tripLossMW / Sbase;

fprintf('\nAggregate physical disturbance:\n');

fprintf('  Generator loss              = %.6f MW\n', ...
    tripLossMW);

fprintf('  Pre-UFLS aggregate disturbance = %.6f MW\n', ...
    preUFLSDisturbancePu*Sbase);


fprintf('\nInitial post-trip ROCOF estimate = %.6f Hz/s\n', ...
    initialROCOFEstimate);


%% ========================================================================
% 30. STAGE 1
%
% GENERATOR TRIP -> UFLS TRIGGER
%
% PRE-UFLS network and load remain active.
% =========================================================================

options1 = odeset( ...
    'RelTol',1e-5, ...
    'AbsTol',1e-7, ...
    'Events',@(t,x) ...
        uflsTriggerEvent( ...
            t, ...
            x, ...
            f0, ...
            HsysActive, ...
            fTrigger));


[t1,x1,te,xe,ie] = ...
    ode45( ...
        @(t,x) ...
            localSwingEquations( ...
                t, ...
                x, ...
                YredPre, ...
                Eactive, ...
                Pm0, ...
                HsysActive, ...
                DgenActive, ...
                DloadPreMWHz, ...
                GovGainPuHz, ...
                GovHeadroomPu, ...
                Tgov, ...
                Tturb, ...
                f0, ...
                Sbase, ...
                omega_s, ...
                preUFLSDisturbancePu, ...
                true), ...
                [0 simulationTime], ...
                x0, ...
                options1);


%% ========================================================================
% 31. HANDLE UFLS TRIGGER
% =========================================================================

if isempty(te)

    %----------------------------------------------------------------------
    % Trigger not reached.
    % No physical UFLS relay operation occurred.
    % Module 10 may still have calculated a conservative shedding amount.
    %----------------------------------------------------------------------

    fprintf('\n');
    fprintf('UFLS trigger was NOT reached during simulation.\n');
    fprintf('No physical UFLS shedding was activated in Module 11.\n');

    tTrigger = NaN;

    tShedding = NaN;

    physicalUFLSAppliedMW = 0;

    t = t1;

    x = x1;


else

    %----------------------------------------------------------------------
    % Trigger detected.
    %----------------------------------------------------------------------

    tTrigger = te(1);

    tShedding = ...
        tTrigger + UFLSdelay;

    physicalUFLSAppliedMW = actualLoadReduction;

    fprintf('\n');
    fprintf('UFLS trigger detected:\n');

    fprintf('  Trigger time       = %.6f s\n', ...
        tTrigger);

    fprintf('  Trigger frequency  = %.6f Hz\n', ...
        fTrigger);

    fprintf('  Shedding time      = %.6f s\n', ...
        tShedding);


    %% ========================================================================
% 31A. POST-UFLS AGGREGATE DISTURBANCE
% =========================================================================

if isempty(te)

    % No physical UFLS operation occurred.
    physicalUFLSAppliedMW = 0;

else

    % Actual load reduction calculated by Modules 6-10.
    physicalUFLSAppliedMW = actualLoadReduction;

end


postUFLSDisturbanceMW = ...
    -tripLossMW + physicalUFLSAppliedMW;

postUFLSDisturbancePu = ...
    postUFLSDisturbanceMW / Sbase;


fprintf('\nPost-UFLS aggregate physical disturbance:\n');

fprintf('  Generator loss       = %.6f MW\n', ...
    tripLossMW);

fprintf('  Physical UFLS        = %.6f MW\n', ...
    physicalUFLSAppliedMW);

fprintf('  Net disturbance      = %.6f MW\n', ...
    postUFLSDisturbanceMW);




%% ====================================================================
    % 32. STAGE 2
    %
    % UFLS RELAY DELAY
    %
    % PRE-UFLS network/load remain active.
    % =====================================================================

    if UFLSdelay > 0 && ...
       tShedding < simulationTime

        options2 = odeset( ...
            'RelTol',1e-7, ...
            'AbsTol',1e-9);


        [t2,x2] = ...
            ode45( ...
                @(t,x) ...
                    localSwingEquations( ...
                        t, ...
                        x, ...
                        YredPre, ...
                        Eactive, ...
                        Pm0, ...
                        HsysActive, ...
                        DgenActive, ...
                        DloadPreMWHz, ...
                        GovGainPuHz, ...
                        GovHeadroomPu, ...
                Tgov, ...
                Tturb, ...
                f0, ...
                        Sbase, ...
                        omega_s, ...
                        preUFLSDisturbancePu, ...
                        true), ...
                        [tTrigger tShedding], ...
                        xe, ...
                        options2);


    else

        t2 = tTrigger;

        x2 = xe;

    end


    %% ====================================================================
    % 33. STAGE 3
    %
    % ACTUAL UFLS SHEDDING
    %
    % Switch to the actual post-UFLS load/network calculated by
    % Module 10.
    % =====================================================================

    if tShedding < simulationTime

        xShedding = ...
            x2(end,:).';


        options3 = odeset( ...
            'RelTol',1e-7, ...
            'AbsTol',1e-9);


        [t3,x3] = ...
            ode45( ...
                @(t,x) ...
                    localSwingEquations( ...
                        t, ...
                        x, ...
                        YredPost, ...
                        Eactive, ...
                        Pm0, ...
                        HsysActive, ...
                        DgenActive, ...
                        DloadPostMWHz, ...
                        GovGainPuHz, ...
                        GovHeadroomPu, ...
                        Tgov, ...
                        Tturb, ...
                        f0, ...
                        Sbase, ...
                        omega_s, ...
                        postUFLSDisturbancePu, ...
                        true), ...
                        [tShedding simulationTime], ...
                        xShedding, ...
                        options3);


    else

        t3 = [];

        x3 = [];

    end


    %% ====================================================================
    % 34. COMBINE ALL STAGES
    % =====================================================================

    t = t1;

    x = x1;


    if length(t2) > 1

        t = [t;t2(2:end)];

        x = [x;x2(2:end,:)];

    end


    if ~isempty(t3)

        t = [t;t3(2:end)];

        x = [x;x3(2:end,:)];

    end

end

%% ========================================================================
% 35. CALCULATE GENERATOR FREQUENCIES
% =========================================================================

omegaAll = ...
    x(:,nActive+1:2*nActive);


freqGen = ...
    f0 * omegaAll;


%% ========================================================================
% 36. SYSTEM CENTER-OF-INERTIA FREQUENCY
% =========================================================================

weightsCOI = ...
    HsysActive(:);


fCOI = ...
    zeros(length(t),1);


for k = 1:length(t)

    omegaCOI = ...
        sum(weightsCOI .* omegaAll(k,:).') / ...
        sum(weightsCOI);


    fCOI(k) = ...
        f0 * omegaCOI;

end


%% ========================================================================
% 37. FREQUENCY DERIVATIVE
% =========================================================================

if length(t) >= 2

    dfdt = ...
        gradient(fCOI,t);

else

    dfdt = 0;

end


%% ========================================================================
% 38. FREQUENCY RESULTS
% =========================================================================

initialFrequency = ...
    fCOI(1);


initialROCOF = ...
    dfdt(1);


[minFrequency,nadirIndex] = ...
    min(fCOI);


nadirTime = ...
    t(nadirIndex);


finalFrequency = ...
    fCOI(end);

% Final dynamic governor/turbine states for reporting.
finalPgovPu = x(end,2*nActive+1:3*nActive).';
finalPturbPu = x(end,3*nActive+1:4*nActive).';
finalGovernorResponseMW = finalPgovPu * Sbase;
finalTurbineIncrementMW = finalPturbPu * Sbase;
finalMechanicalPowerMW = Pm0 * Sbase + finalTurbineIncrementMW;

% Final electrical power from the POST-UFLS reduced network.
deltaFinal = x(end,1:nActive).';
Efinal = abs(Eactive) .* exp(1j*deltaFinal);
Ifinal = YredPost * Efinal;
PeFinalPu = real(Efinal .* conj(Ifinal));
finalElectricalPowerMW = PeFinalPu * Sbase;

% Final frequency-dependent terms.
finalDeltaF_Hz = finalFrequency - f0;
finalLoadFrequencyResponseMW = DloadPostMWHz * finalDeltaF_Hz;
finalGeneratorDampingMW = ...
    Sbase * sum(DgenActive .* (omegaAll(end,:).' - 1));

% Dynamic power-balance residual. A small value indicates that the
% post-UFLS operating point is dynamically close to equilibrium.
finalNetAccelerationMW = ...
    sum(finalMechanicalPowerMW) ...
    - sum(finalElectricalPowerMW) ...
    - finalGeneratorDampingMW ...
    - finalLoadFrequencyResponseMW;

% The swing equations use per-unit power. Convert the aggregate final
% acceleration power back to an equivalent COI ROCOF for a consistency check.
finalEquivalentROCOF_HzPerS = ...
    f0 * (finalNetAccelerationMW / Sbase) / ...
    (2 * sum(HsysActive));

% Aggregate COI balance actually used by the corrected post-UFLS model.
finalAggregateTargetMismatchMW = ...
    postUFLSDisturbanceMW ...
    + sum(finalTurbineIncrementMW) ...
    - finalLoadFrequencyResponseMW ...
    - finalGeneratorDampingMW;

finalAggregateEquivalentROCOF_HzPerS = ...
    f0 * (finalAggregateTargetMismatchMW / Sbase) / ...
    (2 * sum(HsysActive));

%% ========================================================================
% 39. FINAL SETTLING METRICS
% =========================================================================
%
% Do not use the mean of the last few ODE45 samples as the stability test.
% The sample spacing is adaptive and oscillatory slopes can cancel.
%
% Instead, use a fixed physical-time window and evaluate:
%   1. linear frequency trend over the window, and
%   2. residual peak-to-peak oscillation after removing that trend.
% =========================================================================

stabilityWindow_s = 5.0;
slopeTolerance_HzPerS = 0.01;
peakToPeakTolerance_Hz = 0.05;

windowStart = ...
    max(t(1),t(end)-stabilityWindow_s);

stableIdx = ...
    t >= windowStart;

tStable = ...
    t(stableIdx);

fStable = ...
    fCOI(stableIdx);

if length(tStable) >= 2

    pStable = ...
        polyfit(tStable,fStable,1);

    finalSlope = ...
        pStable(1);

    fTrend = ...
        polyval(pStable,tStable);

    residualStable = ...
        fStable - fTrend;

    finalPeakToPeak = ...
        max(residualStable) - min(residualStable);

    finalRMSOscillation = ...
        sqrt(mean(residualStable.^2));

else

    finalSlope = dfdt(end);
    finalPeakToPeak = 0;
    finalRMSOscillation = 0;

end

% Compare the final simulated COI slope with the aggregate physical
% ROCOF used by the corrected model.
%
% The raw reduced-network ROCOF is intentionally not used for this
% consistency check because the aggregate correction removes the
% constant-E' network power-balance artifact.

finalROCOFConsistencyError_HzPerS = ...
    finalSlope - finalAggregateEquivalentROCOF_HzPerS;


%% ========================================================================
% 40. FREQUENCY TARGET
% =========================================================================

if ~isfield(data,'fTarget') || isempty(data.fTarget)

    error(['Module 11: data.fTarget is missing. ', ...
           'The target frequency must be specified explicitly.']);

end

targetFrequency = data.fTarget(1);


if ~isfinite(targetFrequency)

    error('Module 11: invalid target frequency.');

end


%% ========================================================================
% 41. SECURITY CONDITIONS
% =========================================================================

nadirSecure = ...
    minFrequency >= targetFrequency;


finalRecovered = ...
    finalFrequency >= targetFrequency;


slopeStable = ...
    abs(finalSlope) <= slopeTolerance_HzPerS;

oscillationStable = ...
    finalPeakToPeak <= peakToPeakTolerance_Hz;

fullyStabilized = ...
    slopeStable && oscillationStable;

% Keep frequency security and dynamic settling as separate results.
if nadirSecure && finalRecovered
    frequencySecurityStatus = 'SECURE';
else
    frequencySecurityStatus = 'NOT SECURE';
end

if fullyStabilized
    stabilizationStatus = 'STABILIZED';
else
    stabilizationStatus = 'NOT STABILIZED';
end

if abs(finalFrequency - f0) <= 0.01
    nominalRecoveryStatus = 'RESTORED TO NOMINAL';
else
    nominalRecoveryStatus = 'NOT RESTORED TO NOMINAL';
end


%% ========================================================================
% 42. STORE RESULTS
% =========================================================================

result11.time = t;

result11.freqGen = freqGen;

result11.fCOI = fCOI;

result11.dfdt = dfdt;


result11.activeGen = activeGen;

result11.tripGen = tripGen;


result11.Eprime = EprimeAll;


result11.preLoadMW = preLoadMW;

result11.postLoadMW = postLoadMW;

result11.actualLoadReductionMW = ...
    actualLoadReduction;

result11.physicalUFLSAppliedMW = ...
    physicalUFLSAppliedMW;

result11.tripLossMW = ...
    tripLossMW;

result11.postUFLSDisturbanceMW = ...
    postUFLSDisturbanceMW;


result11.f0 = f0;

result11.targetFrequency = ...
    targetFrequency;

result11.triggerFrequency = ...
    fTrigger;

result11.UFLSdelay = ...
    UFLSdelay;


result11.triggerTime = ...
    tTrigger;

result11.sheddingTime = ...
    tShedding;


result11.initialFrequency = ...
    initialFrequency;

result11.initialROCOF = ...
    initialROCOF;

result11.initialROCOFEstimate = ...
    initialROCOFEstimate;


result11.minimumFrequency = ...
    minFrequency;

result11.nadirTime = ...
    nadirTime;

result11.finalFrequency = ...
    finalFrequency;

result11.finalSlope = ...
    finalSlope;

result11.stabilityWindow_s = ...
    stabilityWindow_s;

result11.slopeTolerance_HzPerS = ...
    slopeTolerance_HzPerS;

result11.peakToPeakTolerance_Hz = ...
    peakToPeakTolerance_Hz;

result11.finalPeakToPeakOscillation_Hz = ...
    finalPeakToPeak;

result11.finalRMSOscillation_Hz = ...
    finalRMSOscillation;

result11.slopeStable = ...
    slopeStable;

result11.oscillationStable = ...
    oscillationStable;

result11.nadirSecure = ...
    nadirSecure;

result11.finalRecovered = ...
    finalRecovered;

result11.fullyStabilized = ...
    fullyStabilized;

result11.frequencySecurityStatus = ...
    frequencySecurityStatus;

result11.stabilizationStatus = ...
    stabilizationStatus;

result11.nominalRecoveryStatus = ...
    nominalRecoveryStatus;

result11.finalDeltaF_Hz = ...
    finalDeltaF_Hz;

result11.finalElectricalPowerMW = ...
    finalElectricalPowerMW;

result11.finalLoadFrequencyResponseMW = ...
    finalLoadFrequencyResponseMW;

result11.finalGeneratorDampingMW = ...
    finalGeneratorDampingMW;

result11.finalNetAccelerationMW = ...
    finalNetAccelerationMW;

result11.finalEquivalentROCOF_HzPerS = ...
    finalEquivalentROCOF_HzPerS;

result11.finalROCOFConsistencyError_HzPerS = ...
    finalROCOFConsistencyError_HzPerS;
result11.finalAggregateTargetMismatchMW = ...
    finalAggregateTargetMismatchMW;
result11.finalAggregateEquivalentROCOF_HzPerS = ...
    finalAggregateEquivalentROCOF_HzPerS;

result11.simulationTime_s = ...
    simulationTime;


result11.initialPostTripMismatchMW = ...
    totalInitialMismatchMW;


result11.maxEquilibriumErrorMW = ...
    maxEquilibriumError;


% Store dynamic-model parameters for traceability.

result11.governorDroop = ...
    Ractive;

result11.governorGainMWHz = ...
    GovGainMWHz;

result11.governorHeadroomMW = ...
    GovHeadroomMW;

result11.finalGovernorResponseMW = ...
    finalGovernorResponseMW;

result11.finalTurbineIncrementMW = ...
    finalTurbineIncrementMW;

result11.finalMechanicalPowerMW = ...
    finalMechanicalPowerMW;

result11.governorTimeConstant_s = ...
    Tgov;

result11.turbineTimeConstant_s = ...
    Tturb;

result11.loadDampingPreMWHz = ...
    DloadPreMWHz;

result11.loadDampingPostMWHz = ...
    DloadPostMWHz;

result11.HsysActive = ...
    HsysActive;


%% ========================================================================
% 43. PRINT FINAL RESULTS
% =========================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' MODULE 11 RESULTS\n');
fprintf('============================================================\n');


fprintf('\nGenerator contingency:\n');

fprintf('  Tripped generator : Gen %d\n',tripGen);

fprintf('  Tripped bus       : Bus %d\n',genBus(tripGen));


fprintf('\nLoad conditions:\n');

fprintf('  Pre-UFLS load        = %.4f MW\n', ...
    preLoadMW);

fprintf('  Post-UFLS load       = %.4f MW\n', ...
    postLoadMW);

fprintf('  Actual load shedding = %.4f MW\n', ...
    actualLoadReduction);


fprintf('\nFrequency response:\n');

fprintf('  Initial COI frequency = %.6f Hz\n', ...
    initialFrequency);

fprintf('  Initial ROCOF         = %.6f Hz/s\n', ...
    initialROCOF);


if isnan(tTrigger)

    fprintf('  UFLS trigger time     = NOT REACHED\n');

else

    fprintf('  UFLS trigger time     = %.6f s\n', ...
        tTrigger);

end


if isnan(tShedding)

    fprintf('  UFLS shedding time    = NOT APPLIED\n');

else

    fprintf('  UFLS shedding time    = %.6f s\n', ...
        tShedding);

end


fprintf('  Minimum COI frequency = %.6f Hz\n', ...
    minFrequency);

fprintf('  Nadir time            = %.6f s\n', ...
    nadirTime);

fprintf('  Final COI frequency   = %.6f Hz\n', ...
    finalFrequency);


fprintf('\nFrequency target:\n');

fprintf('  Target frequency      = %.6f Hz\n', ...
    targetFrequency);


fprintf('\nNadir security condition:\n');

if nadirSecure

    fprintf('  SATISFIED\n');

else

    fprintf('  NOT SATISFIED\n');

end


fprintf('\nFinal frequency condition:\n');

if finalRecovered

    fprintf('  RECOVERED TO TARGET\n');

else

    fprintf('  DID NOT RECOVER TO TARGET\n');

end


fprintf('\nFinal dynamic governor/turbine response:\n');
for k = 1:nActive
    g = activeGen(k);
    fprintf(['  Gen %2d: Governor = %.4f MW, ', ...
             'Turbine increment = %.4f MW, ', ...
             'Mechanical Pm = %.4f MW\n'], ...
        g, finalGovernorResponseMW(k), ...
        finalTurbineIncrementMW(k), ...
        finalMechanicalPowerMW(k));
end

fprintf('  Total final governor response = %.6f MW\n', ...
    sum(finalGovernorResponseMW));

fprintf('\nFinal dynamic power-balance diagnostic:\n');
fprintf('  Mechanical power          = %.6f MW\n', ...
    sum(finalMechanicalPowerMW));
fprintf('  Electrical power          = %.6f MW\n', ...
    sum(finalElectricalPowerMW));
fprintf('  Generator damping         = %.6f MW\n', ...
    finalGeneratorDampingMW);
fprintf('  Load-frequency response   = %.6f MW\n', ...
    finalLoadFrequencyResponseMW);
fprintf('  Raw network acceleration = %.6f MW\n', ...
    finalNetAccelerationMW);
fprintf('  Raw-network COI ROCOF    = %.8f Hz/s\n', ...
    finalEquivalentROCOF_HzPerS);
fprintf('  Corrected aggregate imbalance = %.6f MW\n', ...
    finalAggregateTargetMismatchMW);
fprintf('  Corrected aggregate COI ROCOF = %.8f Hz/s\n', ...
    finalAggregateEquivalentROCOF_HzPerS);
fprintf('  ROCOF consistency error  = %.8f Hz/s\n', ...
    finalROCOFConsistencyError_HzPerS);


%% ========================================================================
% 44. FINAL GENERATOR FREQUENCIES
% =========================================================================

fprintf('\nFinal generator frequencies:\n');


for k = 1:nActive

    g = activeGen(k);


    fprintf('  Gen %2d: %.6f Hz\n', ...
        g, ...
        freqGen(end,k));

end


fprintf('\nFinal COI frequency slope = %.8f Hz/s\n', ...
    finalSlope);

fprintf('Final 5-s trend slope = %.8f Hz/s\n',finalSlope);
fprintf('Final 5-s residual peak-to-peak = %.6f Hz\n',finalPeakToPeak);
fprintf('Final 5-s residual RMS = %.6f Hz\n',finalRMSOscillation);



fprintf('Frequency security status: %s\n', ...
    frequencySecurityStatus);
fprintf('Dynamic stabilization status: %s\n', ...
    stabilizationStatus);
fprintf('Nominal 50-Hz recovery status: %s\n', ...
    nominalRecoveryStatus);

if fullyStabilized
    fprintf('Frequency status: FULLY STABILIZED\n');
else
    fprintf('Frequency status: NOT FULLY STABILIZED\n');
end


%% ========================================================================
% 45. PLOT GENERATOR FREQUENCY
% =========================================================================

figure( ...
    'Name','Generator Frequency Excursion', ...
    'NumberTitle','off');


plot(t,freqGen,'LineWidth',1.1);

hold on;


yline( ...
    targetFrequency, ...
    '--', ...
    'Target', ...
    'LineWidth',1.0);


if ~isnan(tTrigger)

    xline( ...
        tTrigger, ...
        '--', ...
        'UFLS Trigger', ...
        'LineWidth',1.0);

end


if ~isnan(tShedding)

    xline( ...
        tShedding, ...
        '--', ...
        'UFLS Shed', ...
        'LineWidth',1.0);

end


grid on;

xlabel('Time (s)');

ylabel('Frequency (Hz)');

title(sprintf( ...
    'Generator Frequency Excursion - Gen %d Outage (Bus %d)', ...
    op.tripGen, data.genBus(op.tripGen)));

legendStrings = ...
    cell(nActive+1,1);


for k = 1:nActive

    legendStrings{k} = ...
        sprintf('Gen %d',activeGen(k));

end


legendStrings{nActive+1} = ...
    'Target';


legend( ...
    legendStrings, ...
    'Location','best');


hold off;


%% ========================================================================
% 46. PLOT COI FREQUENCY
% =========================================================================

figure( ...
    'Name','System Center-of-Inertia Frequency', ...
    'NumberTitle','off');


plot(t,fCOI,'LineWidth',1.5);

hold on;


yline( ...
    targetFrequency, ...
    '--', ...
    'Target', ...
    'LineWidth',1.0);


if ~isnan(tTrigger)

    xline( ...
        tTrigger, ...
        '--', ...
        'UFLS Trigger', ...
        'LineWidth',1.0);

end


if ~isnan(tShedding)

    xline( ...
        tShedding, ...
        '--', ...
        'UFLS Shed', ...
        'LineWidth',1.0);

end


grid on;

xlabel('Time (s)');

ylabel('COI Frequency (Hz)');

title(sprintf( ...
    'System Center-of-Inertia Frequency - Gen %d Outage (Bus %d)', ...
    op.tripGen, data.genBus(op.tripGen)));

legend( ...
    sprintf('COI Frequency - Gen %d Tripped',op.tripGen), ...
    'Target', ...
    'Location','best');

hold off;


%% ========================================================================
% 47. FINAL SUMMARY
% =========================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' MODULE 11 COMPLETE\n');
fprintf('============================================================\n');


fprintf(['Gen-%d trip -> UFLS trigger -> ', ...
         'UFLS shedding -> post-UFLS response\n'], ...
    tripGen);


fprintf('Minimum COI frequency : %.4f Hz\n', ...
    minFrequency);


fprintf('Final COI frequency   : %.4f Hz\n', ...
    finalFrequency);


fprintf('Load shed             : %.4f MW\n', ...
    actualLoadReduction);


fprintf('Maximum E'' equilibrium error : %.6f MW\n', ...
    maxEquilibriumError);


fprintf('Initial post-trip mismatch   : %.6f MW\n', ...
    totalInitialMismatchMW);


if finalRecovered
    fprintf('RESULT: FREQUENCY RECOVERED TO TARGET\n');
else
    fprintf('RESULT: FREQUENCY DID NOT RECOVER TO TARGET\n');
end

if fullyStabilized
    fprintf('RESULT: FREQUENCY FULLY STABILIZED\n');
else
    fprintf('RESULT: FREQUENCY NOT FULLY STABILIZED\n');
end

if abs(finalFrequency - f0) <= 0.01
    fprintf('RESULT: FREQUENCY RESTORED TO NOMINAL 50 Hz\n');
else
    fprintf('RESULT: FREQUENCY STABILIZED BELOW NOMINAL 50 Hz\n');
end


fprintf('============================================================\n');


end



%% ========================================================================
% LOCAL FUNCTION 1
% BUILD LOAD ADMITTANCE
% =========================================================================

function Yload = ...
    buildLoadAdmittance(data,opState,Vmag)

nBus = ...
    length(data.bus);


Sbase = ...
    data.Sbase(1);


Yload = ...
    zeros(nBus,nBus);


Vmag = ...
    abs(Vmag(:));


if length(Vmag) ~= nBus

    error(['Module 11: voltage vector length does not ', ...
           'match bus count.']);

end


if ~isfield(opState,'Pload') || ...
   ~isfield(opState,'Qload')

    error('Module 11: operating condition is missing Pload/Qload.');

end


PloadVector = ...
    opState.Pload(:);


QloadVector = ...
    opState.Qload(:);


if length(PloadVector) ~= nBus

    error('Module 11: Pload vector does not match bus count.');

end


if length(QloadVector) ~= nBus

    error('Module 11: Qload vector does not match bus count.');

end


for i = 1:nBus

    if Vmag(i) < 1e-8

        error(['Module 11: invalid near-zero voltage ', ...
               'at Bus %d.'], ...
            data.bus(i));

    end


    %--------------------------------------------------------------
    % Bus load
    %--------------------------------------------------------------

    Pload = ...
        PloadVector(i);


    Qload = ...
        QloadVector(i);


    %--------------------------------------------------------------
    % Solar generation
    %
    % Solar active power is treated as negative load.
    %--------------------------------------------------------------

    Psolar = ...
        0;


    if isfield(data,'solarBus') && ...
       isfield(opState,'Psolar')

        solarBus = ...
            data.solarBus(:);

        PsolarVector = ...
            opState.Psolar(:);


        for s = 1:length(solarBus)

            if solarBus(s) == data.bus(i)

                if s <= length(PsolarVector)

                    Psolar = ...
                        Psolar + PsolarVector(s);

                end

            end

        end

    end


    %--------------------------------------------------------------
    % Net passive-network consumption
    %--------------------------------------------------------------

    Pnet = ...
        Pload - Psolar;


    Qnet = ...
        Qload;


    Snet = ...
        Pnet + 1j*Qnet;


    %--------------------------------------------------------------
    % Constant impedance equivalent
    %
    % Y = conj(S)/|V|^2
    %
    % P and Q are assumed to be on system base.
    %--------------------------------------------------------------

    Yload(i,i) = ...
        conj(Snet) / ...
        (Vmag(i)^2);

end


end



%% ========================================================================
% LOCAL FUNCTION 2
% BUILD REDUCED GENERATOR NETWORK
% =========================================================================

function Yred = buildReducedNetwork( ...
    Ybus, ...
    Yload, ...
    genBus, ...
    activeGen, ...
    Xd1System, ...
    data)

%==========================================================================
% BUILDREDUCEDNETWORK
%
% Builds the reduced admittance matrix seen from the generator internal
% transient EMFs E'.
%
% Xd1System may contain:
%   1. all generator Xd' values, or
%   2. only active-generator Xd' values.
%
% If all-generator values are supplied, the active-generator values are
% selected automatically.
%==========================================================================

    activeGen = activeGen(:);
    genBus = genBus(:);
    Xd1System = Xd1System(:);

    nActive = length(activeGen);
    nAllGen = length(genBus);

    %----------------------------------------------------------------------
    % Select Xd' values corresponding to active generators
    %----------------------------------------------------------------------

    if length(Xd1System) == nAllGen

        % Full generator vector was supplied.
        Xd1Active = Xd1System(activeGen);

    elseif length(Xd1System) == nActive

        % Already an active-generator vector.
        Xd1Active = Xd1System;

    else

        error(['buildReducedNetwork: Xd1System length (%d) is incompatible ', ...
               'with total generators (%d) and active generators (%d).'], ...
               length(Xd1System), ...
               nAllGen, ...
               nActive);

    end

    %----------------------------------------------------------------------
    % Check dimensions
    %----------------------------------------------------------------------

    nBus = size(Ybus,1);

    if size(Ybus,2) ~= nBus
        error('buildReducedNetwork: Ybus must be square.');
    end

    if ~isequal(size(Yload),size(Ybus))
        error('buildReducedNetwork: Yload dimensions do not match Ybus.');
    end

    if any(activeGen < 1) || any(activeGen > nAllGen)
        error('buildReducedNetwork: invalid active generator index.');
    end

    if any(~isfinite(Xd1Active)) || any(Xd1Active <= 0)
        error('buildReducedNetwork: invalid active-generator Xd'' values.');
    end

    %----------------------------------------------------------------------
    % Map generator bus numbers to actual Ybus matrix indices
    %----------------------------------------------------------------------

    genBusIndex = zeros(nActive,1);

    for k = 1:nActive

        g = activeGen(k);

        busNumber = genBus(g);

        idx = find(data.bus == busNumber,1);

        if isempty(idx)

            error(['buildReducedNetwork: generator %d is assigned to ', ...
                   'Bus %d, but that bus was not found in data.bus.'], ...
                   g, ...
                   busNumber);

        end

        genBusIndex(k) = idx;

    end

    %----------------------------------------------------------------------
    % Check duplicate generator buses
    %----------------------------------------------------------------------

    if length(unique(genBusIndex)) ~= nActive

        error(['buildReducedNetwork: duplicate bus detected among ', ...
               'active generators.']);

    end

    %----------------------------------------------------------------------
    % Base network including constant-impedance loads
    %----------------------------------------------------------------------

    Ynetwork = Ybus + Yload;

    %----------------------------------------------------------------------
    % Generator transient admittances
    %
    % Yg = 1/(jXd')
    %----------------------------------------------------------------------

    Yg = diag(1 ./ (1j .* Xd1Active));

    %----------------------------------------------------------------------
    % Add generator transient admittances at generator terminal buses
    %----------------------------------------------------------------------

    Yaug = Ynetwork;

    for k = 1:nActive

        b = genBusIndex(k);

        Yaug(b,b) = ...
            Yaug(b,b) + Yg(k,k);

    end

    %----------------------------------------------------------------------
    % Separate generator terminal buses and remaining buses
    %----------------------------------------------------------------------

    allBus = (1:nBus).';

    nonGenBusIndex = ...
        setdiff(allBus,genBusIndex);

    %----------------------------------------------------------------------
    % Kron reduction to generator terminal buses
    %----------------------------------------------------------------------

    Ygg = ...
        Yaug(genBusIndex,genBusIndex);

    if isempty(nonGenBusIndex)

        Yterminal = Ygg;

    else

        Ygn = ...
            Yaug(genBusIndex,nonGenBusIndex);

        Yng = ...
            Yaug(nonGenBusIndex,genBusIndex);

        Ynn = ...
            Yaug(nonGenBusIndex,nonGenBusIndex);

        Yterminal = ...
            Ygg - Ygn * (Ynn \ Yng);

    end

    %----------------------------------------------------------------------
    % Convert terminal-bus network to generator internal-E' network
    %
    % I = Yg(E' - V)
    %
    % I = Yterminal V
    %
    % Therefore:
    %
    % Yred = Yg - Yg*inv(Yterminal)*Yg
    %----------------------------------------------------------------------

    Yred = ...
        Yg - Yg * (Yterminal \ Yg);

end



%% ========================================================================
% LOCAL FUNCTION 3
% SWING + GOVERNOR + TURBINE EQUATIONS
% =========================================================================

function dx = ...
    localSwingEquations( ...
        t, ...
        x, ...
        Yred, ...
        Eactive, ...
        Pm0, ...
        Hsys, ...
        Dgen, ...
        DloadMWHz, ...
        GovGainPuHz, ...
        GovHeadroomPu, ...
        Tgov, ...
        Tturb, ...
        f0, ...
        Sbase, ...
        omega_s, ...
        aggregateDisturbancePu, ...
        useAggregateCorrection)

% t is retained for ODE45 compatibility.

nGen = length(Pm0);

%--------------------------------------------------------------------------
% Separate state variables.
%--------------------------------------------------------------------------
delta = x(1:nGen);
omega = x(nGen+1:2*nGen);
Pgov  = x(2*nGen+1:3*nGen);
Pturb = x(3*nGen+1:4*nGen);

%--------------------------------------------------------------------------
% Generator internal transient EMFs.
%--------------------------------------------------------------------------
E = abs(Eactive) .* exp(1j*delta);

%--------------------------------------------------------------------------
% Network currents and electrical powers.
%--------------------------------------------------------------------------
I = Yred * E;
Pe = real(E .* conj(I));

%--------------------------------------------------------------------------
% System COI frequency.
%--------------------------------------------------------------------------
weights = Hsys(:);
omegaCOI = sum(weights .* omega) / sum(weights);
fCOI = f0 * omegaCOI;
deltaF = fCOI - f0;

%--------------------------------------------------------------------------
% Dynamic governor.
%
% Desired incremental governor response from static droop:
%
%   Pcmd = -Kgov * DeltaF
%
% Only positive response is allowed for under-frequency operation, and
% each generator is limited by its available headroom.
%--------------------------------------------------------------------------
PgovCommand = -GovGainPuHz .* deltaF;
PgovCommand = max(PgovCommand,0);
PgovCommand = min(PgovCommand,GovHeadroomPu);

dPgov = ...
    (PgovCommand - Pgov) ./ Tgov;

%--------------------------------------------------------------------------
% Turbine response follows the governor output with a separate time lag.
%--------------------------------------------------------------------------
dPturb = ...
    (Pgov - Pturb) ./ Tturb;

%--------------------------------------------------------------------------
% Total mechanical power entering the swing equation.
%--------------------------------------------------------------------------
Pm = Pm0 + Pturb;

%--------------------------------------------------------------------------
% Load-frequency response.
% Negative DeltaF reduces the effective load.
%--------------------------------------------------------------------------
deltaPloadTotalPu = ...
    DloadMWHz * deltaF / Sbase;

% Distribute aggregate load-frequency response according to inertia.
if sum(Hsys) > 0
    loadShare = Hsys / sum(Hsys);
else
    loadShare = ones(nGen,1) / nGen;
end

deltaPloadIndividual = ...
    deltaPloadTotalPu .* loadShare;

%--------------------------------------------------------------------------
% Generator damping.
%--------------------------------------------------------------------------
deltaPgenDamping = ...
    Dgen .* (omega - 1);

%--------------------------------------------------------------------------
% Swing equations.
%
% During the generator-trip and UFLS-delay stages, retain the existing
% detailed reduced-network swing equation.
%
% After UFLS, however, constant-E' reduced-network power can contain a
% non-physical aggregate offset because the generator internal voltages
% are frozen while the operating point has changed. Therefore the COI
% acceleration is anchored to the actual system-level disturbance: 
%
%   aggregate imbalance = generator loss + actual load shedding
%                       + governor response
%                       - load-frequency response
%                       - generator damping
%
% The difference between this physical aggregate balance and the raw
% reduced-network mismatch is distributed according to inertia. This keeps
% relative generator-angle dynamics while preventing the reduced network
% approximation from changing the intended aggregate frequency equilibrium.
%--------------------------------------------------------------------------
ddelta = ...
    omega_s .* (omega - 1);

rawMismatch = ...
    Pm ...
    - Pe ...
    - deltaPgenDamping ...
    - deltaPloadIndividual;

if useAggregateCorrection

    aggregateTargetMismatch = ...
        aggregateDisturbancePu ...
        + sum(Pturb) ...
        - deltaPloadTotalPu ...
        - sum(deltaPgenDamping);

    rawAggregateMismatch = sum(rawMismatch);

    correctionPu = ...
        aggregateTargetMismatch - rawAggregateMismatch;

    if sum(Hsys) > 0
        correctionShare = Hsys / sum(Hsys);
    else
        correctionShare = ones(nGen,1) / nGen;
    end

    domega = ...
        (rawMismatch + correctionPu .* correctionShare) ./ ...
        (2 .* Hsys);

else

    domega = ...
        rawMismatch ./ ...
        (2 .* Hsys);

end

dx = ...
    [ddelta;domega;dPgov;dPturb];

end


%% ========================================================================
% LOCAL FUNCTION 4
% UFLS TRIGGER EVENT
% =========================================================================

function [value,isterminal,direction] = ...
    uflsTriggerEvent( ...
        t, ...
        x, ...
        f0, ...
        Hsys, ...
        fTrigger)

% t is retained for ODE45 event-function compatibility.

 %#ok<INUSD>


nGen = ...
    length(Hsys);


% Generator speeds

omega = ...
    x(nGen+1:2*nGen);


% COI speed

weights = ...
    Hsys(:);


omegaCOI = ...
    sum(weights .* omega) / ...
    sum(weights);


% COI frequency

fCOI = ...
    f0 * omegaCOI;


% Event:
%
%   value = 0
%
% when COI frequency reaches UFLS trigger.
%--------------------------------------------------------------------------

value = ...
    fCOI - fTrigger;


% Stop integration.

isterminal = ...
    1;


% Detect only downward crossing.

direction = ...
    -1;

end